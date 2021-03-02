import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { Cauldron } from '../typechain/Cauldron'
import { Ladle } from '../typechain/Ladle'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock as ERC20 } from '../typechain/ERC20Mock'
import { OracleMock as Oracle } from '../typechain/OracleMock'

import { YieldEnvironment, WAD, RAY, THREE_MONTHS } from './shared/fixtures'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle
const timeMachine = require('ether-time-traveler')

describe('Cauldron - Level', () => {
  let snapshotId: any
  let ownerAcc: SignerWithAddress
  let owner: string
  let env: YieldEnvironment
  let cauldron: Cauldron
  let ladle: Ladle
  let fyToken: FYToken
  let base: ERC20
  let ilk: ERC20
  let spotOracle: Oracle
  let rateOracle: Oracle

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  let vaultId: string

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    snapshotId = await timeMachine.takeSnapshot(ethers.provider)
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  after(async () => {
    await timeMachine.revertToSnapshot(ethers.provider, snapshotId)
  })

  beforeEach(async function () {
    this.timeout(0)
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20
    ilk = env.assets.get(ilkId) as ERC20
    rateOracle = env.oracles.get('rate') as Oracle
    spotOracle = env.oracles.get(ilkId) as Oracle
    fyToken = env.series.get(seriesId) as FYToken
    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string

    await spotOracle.setSpot(RAY.mul(2))
    await ladle.stir(vaultId, WAD, WAD)
  })

  it('before maturity, level is ink * spot - art * ratio', async () => {
    const ink = (await cauldron.balances(vaultId)).ink
    const art = (await cauldron.balances(vaultId)).art
    for (let spot of [1, 2, 4]) {
      await spotOracle.setSpot(RAY.mul(spot))
      for (let ratio of [50, 100, 200]) {
        await cauldron.setSpotOracle(baseId, ilkId, spotOracle.address, ratio * 100)
        const expectedLevel = ink.mul(spot).sub(art.mul(ratio).div(100))
        expect(await cauldron.level(vaultId)).to.equal(expectedLevel)
        // console.log(`${ink} * ${RAY.mul(spot)} - ${art} * ${ratio} = ${await cauldron.level(vaultId)} | ${expectedLevel} `)
      }
    }
  })

  it('before maturity, diff is ink * spot - art * ratio', async () => {
    for (let spot of [1, 2, 4]) {
      await spotOracle.setSpot(RAY.mul(spot))
      for (let ratio of [50, 100, 200]) {
        await cauldron.setSpotOracle(baseId, ilkId, spotOracle.address, ratio * 100)
        for (let ink of [WAD, WAD.mul(-1)]) {
          for (let art of [WAD, WAD.mul(-1)]) {
            const expectedDiff = ink.mul(spot).sub(art.mul(ratio).div(100))
            expect(await cauldron.diff(vaultId, ink, art)).to.equal(expectedDiff)
          }
        }
      }
    }
  })

  it('after maturity, level is ink * spot - art * accrual * ratio', async () => {
    await spotOracle.setSpot(RAY.mul(1))
    await rateOracle.setSpot(RAY.mul(1))
    await timeMachine.advanceTimeAndBlock(ethers.provider, THREE_MONTHS)
    await rateOracle.record(await fyToken.maturity())

    const ink = (await cauldron.balances(vaultId)).ink
    const art = (await cauldron.balances(vaultId)).art
    for (let spot of [1, 2, 4]) {
      await spotOracle.setSpot(RAY.mul(spot))
      for (let rate of [110, 120, 140]) {
        await rateOracle.setSpot(RAY.mul(rate).div(100))
        // accrual = rate / 100
        for (let ratio of [50, 100, 200]) {
          await cauldron.setSpotOracle(baseId, ilkId, spotOracle.address, ratio * 100)
          const expectedLevel = ink.mul(spot).sub(art.mul(rate).mul(ratio).div(10000))
          expect(await cauldron.level(vaultId)).to.equal(expectedLevel)
          // console.log(`${ink} * ${RAY.mul(spot)} - ${art} * ${ratio} = ${await cauldron.level(vaultId)} | ${expectedLevel} `)
        }
      }
    }
  })

  it('after maturity, diff is ink * spot - art * accrual * ratio', async () => {
    await spotOracle.setSpot(RAY.mul(1))
    await rateOracle.setSpot(RAY.mul(1))
    await timeMachine.advanceTimeAndBlock(ethers.provider, THREE_MONTHS)
    await rateOracle.record(await fyToken.maturity())

    for (let spot of [1, 2, 4]) {
      await spotOracle.setSpot(RAY.mul(spot))
      for (let rate of [110, 120, 140]) {
        await rateOracle.setSpot(RAY.mul(rate).div(100))
        // accrual = rate / 100
        for (let ratio of [50, 100, 200]) {
          await cauldron.setSpotOracle(baseId, ilkId, spotOracle.address, ratio * 100)
          for (let ink of [WAD, WAD.mul(-1)]) {
            for (let art of [WAD, WAD.mul(-1)]) {
              const expectedDiff = ink.mul(spot).sub(art.mul(rate).mul(ratio).div(10000))
              expect(await cauldron.diff(vaultId, ink, art)).to.equal(expectedDiff)
            }
          }
        }
      }
    }
  })

  it("users can't borrow and become undercollateralized", async () => {
    await expect(ladle.stir(vaultId, 0, WAD.mul(2))).to.be.revertedWith('Undercollateralized')
  })

  it("users can't withdraw and become undercollateralized", async () => {
    await expect(ladle.stir(vaultId, WAD.mul(-1), 0)).to.be.revertedWith('Undercollateralized')
  })
})
