import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { ETH } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { WETH9Mock } from '../typechain/WETH9Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'

describe('Ladle - eth', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let wethJoin: Join
  let ladle: LadleWrapper
  let weth: WETH9Mock

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
  const ethId = ETH

  let ethVaultId: string
  let ilkVaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    wethJoin = env.joins.get(ethId) as Join
    weth = (await ethers.getContractAt('WETH9Mock', await wethJoin.asset())) as WETH9Mock

    ethVaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ethId) as string
    ilkVaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
  })

  it('pouring without sending ETH first reverts', async () => {
    await weth.approve(wethJoin.address, 0) // Revert the permission that was given during initialization
    await expect(ladle.pour(ethVaultId, owner, WAD, 0)).to.be.revertedWith('ERC20: Insufficient approval')
  })

  it('users can transfer ETH then pour', async () => {
    expect(await ladle.joinEther(ethId, { value: WAD }))
    expect(await ladle.pour(ethVaultId, owner, WAD, 0))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(ethVaultId, seriesId, ethId, WAD, 0)
    expect(await weth.balanceOf(wethJoin.address)).to.equal(WAD)
    expect((await cauldron.balances(ethVaultId)).ink).to.equal(WAD)
  })

  it('users can transfer ETH then pour in a single transaction with batch', async () => {
    await ladle.batch([ladle.joinEtherAction(ethId), ladle.pourAction(ethVaultId, owner, WAD, 0)], { value: WAD })
  })

  it('ladle will only receive from WETH', async () => {
    await expect(ownerAcc.sendTransaction({ to: ladle.address, value: WAD })).to.be.revertedWith(
      'Only receive from WETH'
    )
  })

  describe('with ETH posted', async () => {
    beforeEach(async () => {
      expect(await ladle.joinEther(ethId, { value: WAD }))
      await ladle.pour(ethVaultId, owner, WAD, 0)
    })

    it('users can pour to withdraw ETH', async () => {
      expect(await ladle.pour(ethVaultId, ladle.address, WAD.mul(-1), 0))
        .to.emit(cauldron, 'VaultPoured')
        .withArgs(ethVaultId, seriesId, ethId, WAD.mul(-1), 0)
      expect(await weth.balanceOf(wethJoin.address)).to.equal(0)
      expect((await cauldron.balances(ethVaultId)).ink).to.equal(0)
      expect(await weth.balanceOf(ladle.address)).to.equal(WAD)

      expect(await ladle.exitEther(owner))
        .to.emit(weth, 'Withdrawal')
        .withArgs(ladle.address, WAD)
      expect(await weth.balanceOf(ladle.address)).to.equal(0)
    })

    it('users can pour then unwrap to ETH in a single transaction with batch', async () => {
      await ladle.batch([ladle.pourAction(ethVaultId, ladle.address, WAD.mul(-1), 0), ladle.exitEtherAction(owner)])
    })
  })

  describe('with ETH posted and positive debt', async () => {
    beforeEach(async () => {
      expect(await ladle.joinEther(ethId, { value: WAD }))
      await ladle.pour(ethVaultId, owner, WAD, WAD)
    })

    it('users can close to post ETH', async () => {
      expect(await ladle.joinEther(ethId, { value: WAD }))
      expect(await ladle.close(ethVaultId, owner, WAD, WAD.mul(-1)))
        .to.emit(cauldron, 'VaultPoured')
        .withArgs(ethVaultId, seriesId, ethId, WAD, WAD.mul(-1))
      expect(await weth.balanceOf(wethJoin.address)).to.equal(WAD.mul(2))
      expect((await cauldron.balances(ethVaultId)).ink).to.equal(WAD.mul(2))
    })
  })
})
