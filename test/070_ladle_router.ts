import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { WAD, MAX128 as MAX } from './shared/constants'

import { Cauldron } from '../typechain/Cauldron'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { PoolMock } from '../typechain/PoolMock'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'

describe('Ladle - pool router', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let fyToken: FYToken
  let pool: PoolMock
  let base: ERC20Mock
  let ilk: ERC20Mock
  let ladle: Ladle

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockSeriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  let vaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken
    pool = env.pools.get(seriesId) as PoolMock

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
  })

  it('does not allow using unknown pools', async () => {
    await expect(ladle.transferToPool(mockSeriesId, true, WAD)).to.be.revertedWith('Pool not found')
    await expect(ladle.retrieveToken(mockSeriesId, true, other)).to.be.revertedWith('Pool not found')
    await expect(ladle.sellToken(mockSeriesId, true, other, 0)).to.be.revertedWith('Pool not found')
    await expect(ladle.buyToken(mockSeriesId, true, other, WAD.div(2), MAX)).to.be.revertedWith('Pool not found')
  })

  it('transfers base to pool', async () => {
    await base.approve(ladle.address, WAD)
    expect(await ladle.transferToPool(seriesId, true, WAD))
      .to.emit(base, 'Transfer')
      .withArgs(owner, pool.address, WAD)
  })

  it('transfers fyToken to pool', async () => {
    await ladle.pour(vaultId, owner, WAD, WAD)
    await fyToken.approve(ladle.address, WAD)
    expect(await ladle.transferToPool(seriesId, false, WAD))
      .to.emit(fyToken, 'Transfer')
      .withArgs(owner, pool.address, WAD)
  })

  describe('with unaccounted tokens in the pool', async () => {
    beforeEach(async () => {
      await base.mint(pool.address, WAD)
      await fyToken.mint(pool.address, WAD)
    })

    it('retrieves unaccounted tokens in the pool', async () => {
      expect(await ladle.retrieveToken(seriesId, true, other))
        .to.emit(base, 'Transfer')
        .withArgs(pool.address, other, WAD)
      expect(await ladle.retrieveToken(seriesId, false, other))
        .to.emit(fyToken, 'Transfer')
        .withArgs(pool.address, other, WAD)
    })

    it('sells using unaccounted base tokens in the pool', async () => {
      await expect(await ladle.sellToken(seriesId, true, other, 0))
        .to.emit(fyToken, 'Transfer')
        .withArgs(pool.address, other, WAD.mul(105).div(100))
    })

    it('sells using unaccounted fyTokens in the pool', async () => {
      await expect(await ladle.sellToken(seriesId, false, other, 0))
        .to.emit(base, 'Transfer')
        .withArgs(pool.address, other, WAD.mul(100).div(105))
    })

    it('buys using unaccounted base tokens in the pool', async () => {
      await expect(await ladle.buyToken(seriesId, true, other, WAD.div(2), MAX))
        .to.emit(base, 'Transfer')
        .withArgs(pool.address, other, WAD.div(2))
    })

    it('buys using unaccounted fyTokens in the pool', async () => {
      await expect(await ladle.buyToken(seriesId, false, other, WAD.div(2), MAX))
        .to.emit(fyToken, 'Transfer')
        .withArgs(pool.address, other, WAD.div(2))
    })
  })
})
