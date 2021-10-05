import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { RATE, USDC, ETH } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock as ERC20 } from '../typechain/ERC20Mock'
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { CompoundMultiOracle } from '../typechain/CompoundMultiOracle'
import { ISourceMock } from '../typechain/ISourceMock'

import { YieldEnvironment } from './shared/fixtures'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

describe('Cauldron - level', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let env: YieldEnvironment
  let cauldron: Cauldron
  let fyToken: FYToken
  let base: ERC20
  let ilk: ERC20
  let spotOracle: ChainlinkMultiOracle
  let spotSource: ISourceMock
  let rateOracle: CompoundMultiOracle
  let rateSource: ISourceMock

  const oneUSDC = WAD.div(1000000000000)
  const baseId = USDC // We can have only one base in fixtures, so let's do the hard one
  const ilkId = ETH
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  let vaultId: string

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  after(async () => {
    await loadFixture(fixture) // We advance the time to test maturity features, this rolls it back after the tests
  })

  beforeEach(async function () {
    this.timeout(0)
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    base = env.assets.get(baseId) as ERC20
    ilk = env.assets.get(ilkId) as ERC20

    rateOracle = (env.oracles.get(RATE) as unknown) as CompoundMultiOracle
    rateSource = (await ethers.getContractAt('ISourceMock', await rateOracle.sources(baseId, RATE))) as ISourceMock
    spotOracle = (env.oracles.get(ilkId) as unknown) as ChainlinkMultiOracle
    spotSource = (await ethers.getContractAt(
      'ISourceMock',
      (await spotOracle.sources(baseId, ilkId))[0]
    )) as ISourceMock
    fyToken = env.series.get(seriesId) as FYToken
    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string

    await spotSource.set(WAD.div(2500)) // ETH wei per USDC
    await cauldron.pour(vaultId, WAD, oneUSDC.mul(2500))
  })

  it('before maturity, level is ink * spot - art * ratio', async () => {
    const ink = (await cauldron.balances(vaultId)).ink
    const art = (await cauldron.balances(vaultId)).art
    const spots = [WAD.div(2500), WAD.div(5000), WAD.div(10000)]
    for (let spot of spots) {
      await spotSource.set(spot)
      for (let ratio of [50, 100, 200]) {
        await cauldron.setSpotOracle(baseId, ilkId, spotOracle.address, ratio * 10000)
        const reverseSpot = oneUSDC.mul(WAD).div(spot)
        // When setting the oracles, we set them as underlying/collateral matching Chainlink, for which ETH is always the quote.
        // We set for example the USDC/ETH spot to WAD.div(2500), meaning that 1 ETH gets you 2500 USDC, or that 1 USDC gets you 1/2500 of 1 ETH.
        // Then for `level` we want the collateral/underlying spot price (this one ETH collateral, how much USDC is worth?)
        // The reverse is (10**6)*(10**18)/spot (1/spot, in fixed point math with the decimals of the reverse quote (USDC, 6).
        // Finally, to get the value of the collateral we multiply the amount of ETH (ink) by the reverse spot (ETH/USDC) as a fixed point multiplication with the ETH decimals (18) so that the reulst is in USDC.
        const expectedLevel = ink.mul(reverseSpot).div(WAD).sub(art.mul(ratio).div(100))
        // console.log(`${ink} * ${reverseSpot} / ${WAD} - ${art} * ${ratio} = ${await cauldron.callStatic.level(vaultId)} | ${expectedLevel} `)
        expect(await cauldron.callStatic.level(vaultId)).to.equal(expectedLevel)
      }
    }
  })

  it("users can't borrow and become undercollateralized", async () => {
    await expect(cauldron.pour(vaultId, 0, oneUSDC.mul(2))).to.be.revertedWith('Undercollateralized')
  })

  it("users can't withdraw and become undercollateralized", async () => {
    await expect(cauldron.pour(vaultId, oneUSDC.mul(-1), 0)).to.be.revertedWith('Undercollateralized')
  })

  it('does not allow to mature before maturity', async () => {
    await expect(cauldron.mature(seriesId)).to.be.revertedWith('Only after maturity')
  })

  describe('after maturity', async () => {
    beforeEach(async () => {
      await spotSource.set(WAD.mul(1))
      await rateSource.set(WAD.mul(1))
      await ethers.provider.send('evm_mine', [(await fyToken.maturity()).toNumber()])
    })

    it('matures by recording the rate value', async () => {
      expect(await cauldron.mature(seriesId))
        .to.emit(cauldron, 'SeriesMatured')
        .withArgs(seriesId, WAD)
    })

    it("rate accrual can't be below 1", async () => {
      await rateSource.set(WAD.mul(100).div(110))
      expect(await cauldron.callStatic.accrual(seriesId)).to.equal(WAD)
    })

    it('after maturity, level is ink * spot - art * accrual * ratio', async () => {
      await cauldron.level(vaultId)

      const ink = (await cauldron.balances(vaultId)).ink
      const art = (await cauldron.balances(vaultId)).art
      const spots = [WAD.div(2500), WAD.div(5000), WAD.div(10000)]
      for (let spot of spots) {
        await spotSource.set(spot)
        for (let rate of [110, 120, 140]) {
          await rateSource.set(WAD.mul(rate).div(100))
          // accrual = rate / 100
          for (let ratio of [50, 100, 200]) {
            await cauldron.setSpotOracle(baseId, ilkId, spotOracle.address, ratio * 10000)
            const reverseSpot = oneUSDC.mul(WAD).div(spot)
            const expectedLevel = ink.mul(reverseSpot).div(WAD).sub(art.mul(rate).mul(ratio).div(10000))
            expect(await cauldron.callStatic.level(vaultId)).to.equal(expectedLevel)
            // console.log(`${ink} * ${RAY.mul(spot)} - ${art} * ${ratio} = ${await cauldron.level(vaultId)} | ${expectedLevel} `)
          }
        }
      }
    })
  })
})
