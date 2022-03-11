import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { parseUnits } from 'ethers/lib/utils'
import { ethers, waffle } from 'hardhat'
import { DAI, ETH, RATE, USDC } from '../src/constants'
import {
  ChainlinkAggregatorV3Mock__factory,
  ChainlinkMultiOracle,
  CompoundMultiOracle,
  ContangoCauldron,
  ISourceMock,
} from '../typechain'
import { ISourceMock__factory } from '../typechain/factories/ISourceMock__factory'
import { YieldEnvironment } from './shared/contango_fixtures'

const { loadFixture } = waffle

describe.only('ContangoCauldron - global state', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let env: YieldEnvironment
  let cauldron: ContangoCauldron
  let spotOracle1: ChainlinkMultiOracle
  let spotOracle2: ChainlinkMultiOracle
  let spotSource1: ISourceMock
  let spotSource2: ISourceMock
  let spotSource3: ISourceMock
  let rateOracle: CompoundMultiOracle
  let rateSource: ISourceMock

  const baseId = USDC // We can have only one base in fixtures, so let's do the hard one
  const ilkId1 = ETH
  const ilkId2 = DAI
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  let vaultId1: string
  let vaultId2: string

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId1, ilkId2], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
  })

  after(async () => {
    await loadFixture(fixture) // We advance the time to test maturity features, this rolls it back after the tests
  })

  beforeEach(async function () {
    this.timeout(0)
    env = await loadFixture(fixture)
    cauldron = env.cauldron as ContangoCauldron

    rateOracle = (env.oracles.get(RATE) as unknown) as CompoundMultiOracle
    rateSource = ISourceMock__factory.connect(await rateOracle.sources(baseId, RATE), ownerAcc)

    spotOracle1 = (env.oracles.get(ilkId1) as unknown) as ChainlinkMultiOracle
    spotSource1 = ISourceMock__factory.connect((await spotOracle1.sources(baseId, ilkId1))[0], ownerAcc)

    spotOracle2 = (env.oracles.get(ilkId2) as unknown) as ChainlinkMultiOracle
    spotSource2 = ISourceMock__factory.connect((await spotOracle2.sources(baseId, ilkId2))[0], ownerAcc)

    const chainlinkAggregatorV3MockFactory = (await ethers.getContractFactory(
      'ChainlinkAggregatorV3Mock',
      ownerAcc
    )) as ChainlinkAggregatorV3Mock__factory
    spotSource3 = await chainlinkAggregatorV3MockFactory.deploy()
    await spotSource3.deployed()

    await spotOracle1.setSource(
      ilkId2,
      env.assets.get(ilkId2)?.address as string,
      ilkId1,
      env.assets.get(ilkId1)?.address as string,
      spotSource3.address
    )
    await env.cauldron.setSpotOracle(ilkId2, ilkId1, spotOracle1.address, parseUnits('1', 6))

    vaultId1 = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId1) as string
    vaultId2 = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId2) as string

    await spotSource1.set(parseUnits('0.00025')) // ETH per USDC (1 ETH = 4000 USDC)
    await spotSource2.set(parseUnits('1.00001')) // DAI per USDC
    await spotSource3.set(parseUnits('0.000251')) // ETH per DAI (1 ETH = 3984 DAI)
  })

  it('pour updates vault & global balances', async () => {
    const vaultId3 = ethers.utils.formatBytes32String('other').slice(0, 26)
    await env.ladle.deterministicBuild(vaultId3, seriesId, ilkId1)

    // USDCETH vault
    await cauldron.pour(vaultId1, parseUnits('1'), parseUnits('1000', 6))
    expect((await cauldron.balances(vaultId1)).ink).to.equal(parseUnits('1'))
    expect((await cauldron.balances(vaultId1)).art).to.equal(parseUnits('1000', 6))
    expect((await cauldron.balancesPerAsset(ilkId1)).ink).to.equal(parseUnits('1'))
    expect((await cauldron.balancesPerAsset(baseId)).art).to.equal(parseUnits('1000', 6))
    // 1 * 1 - 1000 * 0.00025 * 1.1
    expect(await cauldron.callStatic.getFreeCollateral()).to.equal(parseUnits('0.725'))
    expect(await cauldron.assetsInUseLength()).to.equal(2)

    // USDCDAI vault
    await cauldron.pour(vaultId2, parseUnits('1200'), parseUnits('1000', 6))
    expect((await cauldron.balances(vaultId2)).ink).to.equal(parseUnits('1200'))
    expect((await cauldron.balances(vaultId2)).art).to.equal(parseUnits('1000', 6))
    expect((await cauldron.balancesPerAsset(ilkId1)).ink).to.equal(parseUnits('1'))
    expect((await cauldron.balancesPerAsset(ilkId2)).ink).to.equal(parseUnits('1200'))
    expect((await cauldron.balancesPerAsset(baseId)).art).to.equal(parseUnits('2000', 6))
    // 0.725 + 1200 * 0.000251 - 1000 * 0.00025 * 1.1
    expect(await cauldron.callStatic.getFreeCollateral()).to.equal(parseUnits('0.7512'))
    expect(await cauldron.assetsInUseLength()).to.equal(3)

    // Second USDCETH vault
    await cauldron.pour(vaultId3, parseUnits('10'), parseUnits('20000', 6))
    expect((await cauldron.balances(vaultId3)).ink).to.equal(parseUnits('10'))
    expect((await cauldron.balances(vaultId3)).art).to.equal(parseUnits('20000', 6))
    expect((await cauldron.balancesPerAsset(ilkId1)).ink).to.equal(parseUnits('11'))
    expect((await cauldron.balancesPerAsset(ilkId2)).ink).to.equal(parseUnits('1200'))
    expect((await cauldron.balancesPerAsset(baseId)).art).to.equal(parseUnits('22000', 6))
    // 0.7512 + 10 * 1 - 20000 * 0.00025 * 1.1
    expect(await cauldron.callStatic.getFreeCollateral()).to.equal(parseUnits('5.2512'))
    expect(await cauldron.assetsInUseLength()).to.equal(3)

    // Increase debt on USDCDAI vault
    await cauldron.pour(vaultId2, parseUnits('800'), parseUnits('400', 6))
    expect((await cauldron.balances(vaultId2)).ink).to.equal(parseUnits('2000'))
    expect((await cauldron.balances(vaultId2)).art).to.equal(parseUnits('1400', 6))
    expect((await cauldron.balancesPerAsset(ilkId1)).ink).to.equal(parseUnits('11'))
    expect((await cauldron.balancesPerAsset(ilkId2)).ink).to.equal(parseUnits('2000'))
    expect((await cauldron.balancesPerAsset(baseId)).art).to.equal(parseUnits('22400', 6))
    // 5.2512 + 800 * 0.000251 - 400 * 0.00025 * 1.1
    expect(await cauldron.callStatic.getFreeCollateral()).to.equal(parseUnits('5.342'))
    expect(await cauldron.assetsInUseLength()).to.equal(3)

    // Repay debt and withdraw on USDCETH vault
    await cauldron.pour(vaultId1, parseUnits('-0.6'), parseUnits('-600', 6))
    expect((await cauldron.balances(vaultId1)).ink).to.equal(parseUnits('0.4'))
    expect((await cauldron.balances(vaultId1)).art).to.equal(parseUnits('400', 6))
    expect((await cauldron.balancesPerAsset(ilkId1)).ink).to.equal(parseUnits('10.4'))
    expect((await cauldron.balancesPerAsset(ilkId2)).ink).to.equal(parseUnits('2000'))
    expect((await cauldron.balancesPerAsset(baseId)).art).to.equal(parseUnits('21800', 6))
    // 5.342 + -0.6 * 1 - -600 * 0.00025 * 1.1
    expect(await cauldron.callStatic.getFreeCollateral()).to.equal(parseUnits('4.907'))
    expect(await cauldron.assetsInUseLength()).to.equal(3)

    // Fully repay USDCDAI vault
    await cauldron.pour(vaultId2, parseUnits('-2000'), parseUnits('-1400', 6))
    expect((await cauldron.balances(vaultId2)).ink).to.equal(0)
    expect((await cauldron.balances(vaultId2)).art).to.equal(0)
    expect((await cauldron.balancesPerAsset(ilkId1)).ink).to.equal(parseUnits('10.4'))
    expect((await cauldron.balancesPerAsset(ilkId2)).ink).to.equal(0)
    expect((await cauldron.balancesPerAsset(baseId)).art).to.equal(parseUnits('20400', 6))
    // 4.907 + -2000 * 0.000251 - -1400 * 0.00025 * 1.1
    expect(await cauldron.callStatic.getFreeCollateral()).to.equal(parseUnits('4.79'))
    expect(await cauldron.assetsInUseLength()).to.equal(3)
  })

  it('prunes the assets in use (remove last)', async () => {
    const vaultId3 = ethers.utils.formatBytes32String('other').slice(0, 26)
    await env.ladle.deterministicBuild(vaultId3, seriesId, ilkId1)

    // USDCETH vault
    await cauldron.pour(vaultId1, parseUnits('1'), parseUnits('1000', 6))
    expect(await cauldron.assetsInUseLength()).to.equal(2)
    // USDCDAI vault
    await cauldron.pour(vaultId2, parseUnits('1200'), parseUnits('1000', 6))
    expect(await cauldron.assetsInUseLength()).to.equal(3)

    // Fully repay USDCDAI vault
    await cauldron.pour(vaultId2, parseUnits('-1200'), parseUnits('-1000', 6))
    expect(await cauldron.assetsInUseLength()).to.equal(3)

    expect(await cauldron.callStatic.pruneAssetsInUse()).to.equal(2)
    await cauldron.pruneAssetsInUse()
    expect(await cauldron.assetsInUseLength()).to.equal(2)
  })

  it('prunes the assets in use (remove from middle)', async () => {
    const vaultId3 = ethers.utils.formatBytes32String('other').slice(0, 26)
    await env.ladle.deterministicBuild(vaultId3, seriesId, ilkId1)

    // USDCETH vault
    await cauldron.pour(vaultId1, parseUnits('1'), parseUnits('1000', 6))
    expect(await cauldron.assetsInUseLength()).to.equal(2)
    // USDCDAI vault
    await cauldron.pour(vaultId2, parseUnits('1200'), parseUnits('1000', 6))
    expect(await cauldron.assetsInUseLength()).to.equal(3)

    // Fully repay both vaults (but leave collateral)
    await cauldron.pour(vaultId2, 0, parseUnits('-1000', 6))
    await cauldron.pour(vaultId1, 0, parseUnits('-1000', 6))
    expect(await cauldron.assetsInUseLength()).to.equal(3)

    expect(await cauldron.callStatic.pruneAssetsInUse()).to.equal(2)
    await cauldron.pruneAssetsInUse()
    expect(await cauldron.assetsInUseLength()).to.equal(2)
  })

  it('freeCollateral is ink * inkSpot - art * artSpot * ratio', async () => {
    await cauldron.pour(vaultId2, parseUnits('1200'), parseUnits('1000', 6))
    const ink = (await cauldron.balances(vaultId2)).ink
    const art = (await cauldron.balances(vaultId2)).art

    // 1200*0.000251 - 1000*.00025*1.1
    expect(await cauldron.callStatic.getFreeCollateral()).to.equal(parseUnits('0.0262'))

    const spots = [
      [parseUnits('0.0004'), parseUnits('0.00041')],
      [parseUnits('0.0002'), parseUnits('0.00019')],
      [parseUnits('0.0001'), parseUnits('0.00009')],
    ]
    for (let [inkSpot, artSpot] of spots) {
      await spotSource1.set(artSpot)
      await spotSource3.set(inkSpot)
      for (let ratio of [parseUnits('1.05'), parseUnits('1.1'), parseUnits('1.2')]) {
        cauldron.setCollateralisationRatio(ratio)

        // Ink as ETH
        const inkValuedAsCommonCcy = ink.mul(inkSpot).div(parseUnits('1'))
        // art * 1e12 (bring to 18 digits precision)
        const artValuedAsCommonCcy = art.mul(parseUnits('1', 12)).mul(artSpot).div(parseUnits('1'))
        const artTimesRatio = artValuedAsCommonCcy.mul(ratio).div(parseUnits('1'))

        const expectedFreeCollateral = inkValuedAsCommonCcy.sub(artTimesRatio)
        expect(await cauldron.callStatic.getFreeCollateral()).to.equal(expectedFreeCollateral)
      }
    }
  })

  it("users can't borrow and become undercollateralized", async () => {
    await expect(cauldron.pour(vaultId1, 0, parseUnits('2', 6))).to.be.revertedWith('Vault Undercollateralised')
  })

  it("users can't withdraw and become undercollateralized", async () => {
    await cauldron.pour(vaultId1, parseUnits('1.1'), parseUnits('4000', 6))
    await expect(cauldron.pour(vaultId1, -1, 0)).to.be.revertedWith('Vault Undercollateralised')
  })

  it('pour is authorised', async () => {
    await expect(cauldron.connect((await ethers.getSigners())[10]).pour(vaultId1, 0, 0)).to.be.revertedWith(
      'Access denied'
    )
  })

  it('setCollateralisationRatio is authorised', async () => {
    await expect(cauldron.connect((await ethers.getSigners())[10]).setCollateralisationRatio(0)).to.be.revertedWith(
      'Access denied'
    )
  })

  it('setCommonCurrency is authorised', async () => {
    await expect(cauldron.connect((await ethers.getSigners())[10]).setCommonCurrency(USDC)).to.be.revertedWith(
      'Access denied'
    )
  })

  describe('global vault is collateralised', () => {
    beforeEach(async () => {
      const vaultId3 = ethers.utils.formatBytes32String('other').slice(0, 26)
      await env.ladle.deterministicBuild(vaultId3, seriesId, ilkId1)
      await cauldron.pour(vaultId3, parseUnits('10'), parseUnits('1000', 6))
    })

    it("users can't borrow and become undercollateralized", async () => {
      await expect(cauldron.pour(vaultId1, parseUnits('1.1'), parseUnits('4000.01', 6))).to.be.revertedWith(
        'Vault Undercollateralised'
      )
    })

    it("users can't withdraw and become undercollateralized", async () => {
      await cauldron.pour(vaultId1, parseUnits('1.1'), parseUnits('4000', 6))
      await expect(cauldron.pour(vaultId1, -1, 0)).to.be.revertedWith('Vault Undercollateralised')
    })
  })

  describe('global vault is undercollateralised', () => {
    beforeEach(async () => {
      const vaultId3 = ethers.utils.formatBytes32String('other').slice(0, 26)
      await env.ladle.deterministicBuild(vaultId3, seriesId, ilkId1)
      await cauldron.pour(vaultId3, parseUnits('11'), parseUnits('40000', 6))
      await cauldron.pour(vaultId1, parseUnits('1.1'), parseUnits('4000', 6))

      await spotSource1.set(parseUnits('0.000251')) // ETH per USDC (1 ETH = 3984.06 USDC)
      // -0.0484 * 3984.06 = -192.83 USDC underwater
      await cauldron.getFreeCollateral()
      expect(await cauldron.peekFreeCollateral()).to.equal(parseUnits('-0.0484'))
    })

    it('users can repay debt', async () => {
      await cauldron.pour(vaultId1, 0, -1)
      expect(await cauldron.peekFreeCollateral()).to.equal(parseUnits('-0.0483999997239'))
    })

    it('users can increase collateral', async () => {
      await cauldron.pour(vaultId1, 1, 0)
      expect(await cauldron.peekFreeCollateral()).to.equal(parseUnits('-0.048399999999999999'))
    })

    it('users can open new positions', async () => {
      await cauldron.pour(vaultId2, parseUnits('1200'), parseUnits('1000', 6))
      expect(await cauldron.peekFreeCollateral()).to.equal(parseUnits('-0.0233'))
    })

    it('users can close positions', async () => {
      const ink = (await cauldron.balances(vaultId1)).ink
      const art = (await cauldron.balances(vaultId1)).art
      await cauldron.pour(vaultId1, ink.mul(-1), art.mul(-1))
      expect(await cauldron.peekFreeCollateral()).to.equal(parseUnits('-0.044'))
    })

    it("users can't borrow and become undercollateralized", async () => {
      await expect(cauldron.pour(vaultId1, 0, 1)).to.be.revertedWith('Vault Undercollateralised')
    })

    it("users can't withdraw and become undercollateralized", async () => {
      await expect(cauldron.pour(vaultId1, -1, 0)).to.be.revertedWith('Vault Undercollateralised')
    })
  })
})
