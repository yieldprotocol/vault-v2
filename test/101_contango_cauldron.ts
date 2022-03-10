import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { RATE, USDC, ETH, DAI } from '../src/constants'

import {
  FYToken,
  ERC20Mock as ERC20,
  ChainlinkMultiOracle,
  CompoundMultiOracle,
  ContangoCauldron,
  ISourceMock,
  ChainlinkAggregatorV3Mock__factory,
} from '../typechain'
import { ISourceMock__factory } from '../typechain/factories/ISourceMock__factory'

import { YieldEnvironment } from './shared/contango_fixtures'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
import { formatUnits, parseUnits } from 'ethers/lib/utils'
const { loadFixture } = waffle

describe.only('Cauldron - level', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let env: YieldEnvironment
  let cauldron: ContangoCauldron
  let fyToken: FYToken
  let base: ERC20
  let ilk1: ERC20
  let ilk2: ERC20
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
    otherAcc = signers[1]
    owner = await ownerAcc.getAddress()
  })

  after(async () => {
    await loadFixture(fixture) // We advance the time to test maturity features, this rolls it back after the tests
  })

  beforeEach(async function () {
    this.timeout(0)
    env = await loadFixture(fixture)
    cauldron = env.cauldron as ContangoCauldron
    base = env.assets.get(baseId) as ERC20
    ilk1 = env.assets.get(ilkId1) as ERC20
    ilk2 = env.assets.get(ilkId2) as ERC20

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

    fyToken = env.series.get(seriesId) as FYToken
    vaultId1 = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId1) as string
    vaultId2 = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId2) as string

    await spotSource1.set(parseUnits('0.00025')) // ETH per USDC (1 ETH = 4000 USDC)
    await spotSource2.set(parseUnits('1.00001')) // DAI per USDC
    await spotSource3.set(parseUnits('0.000251')) // ETH per DAI (1 ETH = 3984 DAI)
  })

  // it.only('deterministicBuild is restricted', async () => {
  //   await expect(
  //     ladle
  //       .connect(otherAcc)
  //       .deterministicBuild(ethers.utils.hexlify(ethers.utils.randomBytes(12)), seriesId, ilkId1)
  //   ).to.be.revertedWith('Undercollateralized')
  // })

  it('pour updates vault & global balances', async () => {
    expect((await cauldron.balances(vaultId1)).ink).to.be.eq(parseUnits('0'))
    expect((await cauldron.balances(vaultId1)).art).to.be.eq(parseUnits('0'))
    expect((await cauldron.balances(vaultId2)).ink).to.be.eq(parseUnits('0'))
    expect((await cauldron.balances(vaultId2)).art).to.be.eq(parseUnits('0'))
    expect((await cauldron.balancesPerAsset(ilkId1)).ink).to.be.eq(parseUnits('0'))
    expect((await cauldron.balancesPerAsset(baseId)).art).to.be.eq(parseUnits('0'))

    await cauldron.pour(vaultId1, parseUnits('1'), parseUnits('1000', 6))
    expect((await cauldron.balances(vaultId1)).ink).to.be.eq(parseUnits('1'))
    expect((await cauldron.balances(vaultId1)).art).to.be.eq(parseUnits('1000', 6))
    expect((await cauldron.balancesPerAsset(ilkId1)).ink).to.be.eq(parseUnits('1'))
    expect((await cauldron.balancesPerAsset(baseId)).art).to.be.eq(parseUnits('1000', 6))

    await cauldron.pour(vaultId2, parseUnits('1200'), parseUnits('1000', 6))
    expect((await cauldron.balances(vaultId2)).ink).to.be.eq(parseUnits('1200'))
    expect((await cauldron.balances(vaultId2)).art).to.be.eq(parseUnits('1000', 6))
    expect((await cauldron.balancesPerAsset(ilkId1)).ink).to.be.eq(parseUnits('1'))
    expect((await cauldron.balancesPerAsset(ilkId2)).ink).to.be.eq(parseUnits('1200'))
    expect((await cauldron.balancesPerAsset(baseId)).art).to.be.eq(parseUnits('2000', 6))
  })

  it("before maturity, freeCollateral is ink * inkSpot - art * artSpot' * ratio", async () => {
    await cauldron.pour(vaultId2, parseUnits('1200'), parseUnits('1000', 6))
    const ink = (await cauldron.balances(vaultId2)).ink
    const art = (await cauldron.balances(vaultId2)).art

    // 1200*0.000251 - 1000*.00025*1.1
    expect(await cauldron.callStatic.getFreeCollateral()).to.equal(parseUnits('0.0262'))

    const spots = [[parseUnits('0.0004'), parseUnits("0.00041")], [parseUnits('0.0002'), parseUnits("0.00019")], [parseUnits('0.0001'), parseUnits("0.00009")]]
    for (let [inkSpot, artSpot] of spots) {
      await spotSource1.set(artSpot)
      await spotSource3.set(inkSpot)
      for (let ratio of [parseUnits('1.05'), parseUnits('1.1'), parseUnits('1.2')]) {
        cauldron.setCollateralisationRatio(ratio)

        // Ink as ETH
        const inkValuedAsCommonCcy = ink.mul(inkSpot).div(parseUnits("1"));
        // art * 1e12 (bring to 18 digits precision)
        const artValuedAsCommonCcy = art.mul(parseUnits("1", 12)).mul(artSpot).div(parseUnits("1"))
        const artTimesRatio = artValuedAsCommonCcy.mul(ratio).div(parseUnits("1"))

        const expectedFreeCollateral = inkValuedAsCommonCcy.sub(artTimesRatio)
        expect(await cauldron.callStatic.getFreeCollateral()).to.equal(expectedFreeCollateral)
      }
    }
  })

  it("users can't borrow and become undercollateralized", async () => {
    await expect(cauldron.pour(vaultId1, 0, parseUnits('2', 6))).to.be.revertedWith('Undercollateralised')
  })

  // it("users can't withdraw and become undercollateralized", async () => {
  //   await expect(cauldron.pour(vaultId, oneUSDC.mul(-1), 0)).to.be.revertedWith('Undercollateralized')
  // })

  // it('does not allow to mature before maturity', async () => {
  //   await expect(cauldron.mature(seriesId)).to.be.revertedWith('Only after maturity')
  // })

  // describe('after maturity', async () => {
  //   beforeEach(async () => {
  //     await spotSource.set(WAD.mul(1))
  //     await rateSource.set(WAD.mul(1))
  //     await ethers.provider.send('evm_mine', [(await fyToken.maturity()).toNumber()])
  //   })

  //   it('matures by recording the rate value', async () => {
  //     expect(await cauldron.mature(seriesId))
  //       .to.emit(cauldron, 'SeriesMatured')
  //       .withArgs(seriesId, WAD)
  //   })

  //   it("rate accrual can't be below 1", async () => {
  //     await rateSource.set(WAD.mul(100).div(110))
  //     expect(await cauldron.callStatic.accrual(seriesId)).to.equal(WAD)
  //   })

  //   it('after maturity, level is ink * spot - art * accrual * ratio', async () => {
  //     await cauldron.level(vaultId)

  //     const ink = (await cauldron.balances(vaultId)).ink
  //     const art = (await cauldron.balances(vaultId)).art
  //     const spots = [WAD.div(2500), WAD.div(5000), WAD.div(10000)]
  //     for (let spot of spots) {
  //       await spotSource.set(spot)
  //       for (let rate of [110, 120, 140]) {
  //         await rateSource.set(WAD.mul(rate).div(100))
  //         // accrual = rate / 100
  //         for (let ratio of [50, 100, 200]) {
  //           await cauldron.setSpotOracle(baseId, ilkId1, spotOracle.address, ratio * 10000)
  //           const reverseSpot = oneUSDC.mul(WAD).div(spot)
  //           const expectedLevel = ink.mul(reverseSpot).div(WAD).sub(art.mul(rate).mul(ratio).div(10000))
  //           expect(await cauldron.callStatic.level(vaultId)).to.equal(expectedLevel)
  //           // console.log(`${ink} * ${RAY.mul(spot)} - ${art} * ${ratio} = ${await cauldron.level(vaultId)} | ${expectedLevel} `)
  //         }
  //       }
  //     }
  //   })
  // })
})
