import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { WAD, DEC6 } from './shared/constants'

import { Cauldron } from '../typechain/Cauldron'
import { Ladle } from '../typechain/Ladle'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock as ERC20 } from '../typechain/ERC20Mock'
import { OracleMock as Oracle } from '../typechain/OracleMock'

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
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
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

    await spotOracle.set(DEC6.mul(2))
    await ladle.pour(vaultId, owner, WAD, WAD)
  })

  it('before maturity, level is ink * spot - art * ratio', async () => {
    const ink = (await cauldron.balances(vaultId)).ink
    const art = (await cauldron.balances(vaultId)).art
    for (let spot of [1, 2, 4]) {
      await spotOracle.set(DEC6.mul(spot))
      for (let ratio of [50, 100, 200]) {
        await cauldron.setSpotOracle(baseId, ilkId, spotOracle.address, ratio * 10000, '0x00')
        const expectedLevel = ink.mul(spot).sub(art.mul(ratio).div(100))
        expect(await cauldron.callStatic.level(vaultId)).to.equal(expectedLevel)
        // console.log(`${ink} * ${DEC6.mul(spot)} - ${art} * ${ratio} = ${await cauldron.level(vaultId)} | ${expectedLevel} `)
      }
    }
  })

  it("users can't borrow and become undercollateralized", async () => {
    await expect(ladle.pour(vaultId, owner, 0, WAD.mul(2))).to.be.revertedWith('Undercollateralized')
  })

  it("users can't withdraw and become undercollateralized", async () => {
    await expect(ladle.pour(vaultId, owner, WAD.mul(-1), 0)).to.be.revertedWith('Undercollateralized')
  })

  it('does not allow to mature before maturity', async () => {
    await expect(cauldron.mature(seriesId)).to.be.revertedWith('Only after maturity')
  })

  describe('after maturity', async () => {
    beforeEach(async () => {
      await spotOracle.set(DEC6.mul(1))
      await rateOracle.set(DEC6.mul(1))
      await ethers.provider.send('evm_mine', [(await fyToken.maturity()).toNumber()])
    })

    it('matures by recording the chi value', async () => {
      expect(await cauldron.mature(seriesId))
        .to.emit(cauldron, 'SeriesMatured')
        .withArgs(seriesId, DEC6)
    })

    it('after maturity, level is ink * spot - art * accrual * ratio', async () => {
      await cauldron.level(vaultId)

      const ink = (await cauldron.balances(vaultId)).ink
      const art = (await cauldron.balances(vaultId)).art
      for (let spot of [1, 2, 4]) {
        await spotOracle.set(DEC6.mul(spot))
        for (let rate of [110, 120, 140]) {
          await rateOracle.set(DEC6.mul(rate).div(100))
          // accrual = rate / 100
          for (let ratio of [50, 100, 200]) {
            await cauldron.setSpotOracle(baseId, ilkId, spotOracle.address, ratio * 10000, '0x00')
            const expectedLevel = ink.mul(spot).sub(art.mul(rate).mul(ratio).div(10000))
            expect(await cauldron.callStatic.level(vaultId)).to.equal(expectedLevel)
            // console.log(`${ink} * ${RAY.mul(spot)} - ${art} * ${ratio} = ${await cauldron.level(vaultId)} | ${expectedLevel} `)
          }
        }
      }
    })
  })
})
