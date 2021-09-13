import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { ETH } from '../src/constants'
import { getLastVaultId } from '../src/helpers'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'

describe('Ladle - pour', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock
  let ilkJoin: Join
  let ladle: LadleWrapper
  let ladleFromOther: LadleWrapper

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
  const ilkId = ETH
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  let vaultId: string
  let baseVaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    ladleFromOther = ladle.connect(otherAcc)
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken
    ilkJoin = env.joins.get(ilkId) as Join

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
    await cauldron.setDebtLimits(baseId, ilkId, WAD.mul(2).div(1000000), 1000000, 6)

    baseVaultId = (env.vaults.get(seriesId) as Map<string, string>).get(baseId) as string
  })

  it('only the vault owner can manage its collateral', async () => {
    await expect(ladleFromOther.pour(vaultId, other, WAD, 0)).to.be.revertedWith('Only vault owner')
  })

  it('users can pour to post collateral', async () => {
    expect(await ladle.pour(vaultId, owner, WAD, 0))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, WAD, 0)
    expect(await ilk.balanceOf(ilkJoin.address)).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).ink).to.equal(WAD)
  })

  describe('with posted collateral', async () => {
    beforeEach(async () => {
      await ladle.pour(vaultId, owner, WAD, 0)
      await ladle.pour(baseVaultId, owner, WAD, 0)
    })

    it('users can pour to withdraw collateral', async () => {
      await expect(ladle.pour(vaultId, owner, WAD.mul(-1), 0))
        .to.emit(cauldron, 'VaultPoured')
        .withArgs(vaultId, seriesId, ilkId, WAD.mul(-1), 0)
      expect(await ilk.balanceOf(ilkJoin.address)).to.equal(0)
      expect((await cauldron.balances(vaultId)).ink).to.equal(0)
    })

    it('users can pour to withdraw collateral to others', async () => {
      await expect(ladle.pour(vaultId, other, WAD.mul(-1), 0))
        .to.emit(cauldron, 'VaultPoured')
        .withArgs(vaultId, seriesId, ilkId, WAD.mul(-1), 0)
      expect(await ilk.balanceOf(ilkJoin.address)).to.equal(0)
      expect((await cauldron.balances(vaultId)).ink).to.equal(0)
      expect(await ilk.balanceOf(other)).to.equal(WAD)
    })

    it("users can't borrow under the vault debt limit (dust)", async () => {
      await expect(ladle.pour(vaultId, owner, 0, WAD.div(1000000).sub(1))).to.be.revertedWith('Min debt not reached')
    })

    it('users can pour to borrow fyToken', async () => {
      await expect(ladle.pour(vaultId, owner, 0, WAD))
        .to.emit(cauldron, 'VaultPoured')
        .withArgs(vaultId, seriesId, ilkId, 0, WAD)
      expect(await fyToken.balanceOf(owner)).to.equal(WAD)
      expect((await cauldron.balances(vaultId)).art).to.equal(WAD)
    })

    it('users can be charged a fee when borrowing', async () => {
      const fee = WAD.div(1000000000) // 0.000000 001% wei/second
      await ladle.setFee(fee)
      await ladle.pour(vaultId, owner, 0, WAD)
      const { timestamp } = await ethers.provider.getBlock('latest')
      const appliedFee = (await fyToken.maturity()).sub(timestamp).mul(fee)
      expect(await fyToken.balanceOf(owner)).to.equal(WAD)
      expect((await cauldron.balances(vaultId)).art).to.equal(WAD.add(appliedFee))
    })

    it('except if baseId == ilkId', async () => {
      const fee = WAD.div(1000000000) // 0.000000 001% wei/second
      await ladle.setFee(fee)
      await ladle.pour(baseVaultId, owner, 0, WAD)
      expect(await fyToken.balanceOf(owner)).to.equal(WAD)
      expect((await cauldron.balances(baseVaultId)).art).to.equal(WAD)
    })
  })

  it('users can pour to post collateral and borrow fyToken', async () => {
    await expect(ladle.pour(vaultId, owner, WAD, WAD))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, WAD, WAD)
    expect(await ilk.balanceOf(ilkJoin.address)).to.equal(WAD)
    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).ink).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).art).to.equal(WAD)
  })

  it('users can pour to post collateral from themselves and borrow fyToken to another', async () => {
    const ilkBalanceBefore = await ilk.balanceOf(owner)
    await expect(ladle.pour(vaultId, other, WAD, WAD))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, WAD, WAD)
    expect(await ilk.balanceOf(owner)).to.equal(ilkBalanceBefore.sub(WAD))
    expect(await fyToken.balanceOf(other)).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).ink).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).art).to.equal(WAD)
  })

  describe('with collateral and debt', async () => {
    beforeEach(async () => {
      await ladle.pour(vaultId, owner, WAD, WAD)
    })

    it('users can repay their debt', async () => {
      await fyToken.approve(ladle.address, WAD)
      await expect(ladle.pour(vaultId, owner, 0, WAD.mul(-1)))
        .to.emit(cauldron, 'VaultPoured')
        .withArgs(vaultId, seriesId, ilkId, 0, WAD.mul(-1))
      expect(await fyToken.balanceOf(owner)).to.equal(0)
      expect((await cauldron.balances(vaultId)).art).to.equal(0)
    })

    it('users can repay their debt with a transfer', async () => {
      await fyToken.transfer(fyToken.address, WAD)
      await expect(ladle.pour(vaultId, owner, 0, WAD.mul(-1)))
        .to.emit(cauldron, 'VaultPoured')
        .withArgs(vaultId, seriesId, ilkId, 0, WAD.mul(-1))
      expect(await fyToken.balanceOf(owner)).to.equal(0)
      expect((await cauldron.balances(vaultId)).art).to.equal(0)
    })

    it("users can't repay more debt than they have", async () => {
      await expect(ladle.pour(vaultId, owner, 0, WAD.mul(-2))).to.be.revertedWith('Result below zero')
    })

    it('users can borrow while under the global debt limit (line)', async () => {
      await expect(ladle.pour(vaultId, owner, WAD, WAD))
        .to.emit(cauldron, 'VaultPoured')
        .withArgs(vaultId, seriesId, ilkId, WAD, WAD)
    })

    it("users can't borrow over the global debt limit (line)", async () => {
      await expect(ladle.pour(vaultId, owner, WAD.mul(2), WAD.mul(2))).to.be.revertedWith('Max debt exceeded')
    })
  })
})
