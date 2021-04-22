import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants

import { OPS } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { WETH9Mock } from '../typechain/WETH9Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment, LadleWrapper } from './shared/fixtures'

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
  const ethId = ethers.utils.formatBytes32String('ETH').slice(0, 14)

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
    await expect(ladle.pour(ethVaultId, owner, WAD, 0)).to.be.revertedWith('ERC20: Insufficient balance')
  })

  it('users can transfer ETH then pour', async () => {
    expect(await ladle.joinEther(ethVaultId, ethId, { value: WAD }))
    expect(await ladle.pour(ethVaultId, owner, WAD, 0))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(ethVaultId, seriesId, ethId, WAD, 0)
    expect(await weth.balanceOf(wethJoin.address)).to.equal(WAD)
    expect((await cauldron.balances(ethVaultId)).ink).to.equal(WAD)
  })

  it('users can transfer ETH then pour in a single transaction with batch', async () => {
    const joinEtherData = ethers.utils.defaultAbiCoder.encode(['bytes6'], [ethId])
    const pourData = ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'int128'], [owner, WAD, 0])

    await ladle.ladle.batch(ethVaultId, [OPS.JOIN_ETHER, OPS.POUR], [joinEtherData, pourData], { value: WAD }) // TODO: Fix batch in ladle wrapper
  })

  describe('with ETH posted', async () => {
    beforeEach(async () => {
      expect(await ladle.joinEther(ethVaultId, ethId, { value: WAD }))
      await ladle.pour(ethVaultId, owner, WAD, 0)
    })

    it('users can pour to withdraw ETH', async () => {
      expect(await ladle.pour(ethVaultId, ladle.address, WAD.mul(-1), 0))
        .to.emit(cauldron, 'VaultPoured')
        .withArgs(ethVaultId, seriesId, ethId, WAD.mul(-1), 0)
      expect(await weth.balanceOf(wethJoin.address)).to.equal(0)
      expect((await cauldron.balances(ethVaultId)).ink).to.equal(0)
      expect(await weth.balanceOf(ladle.address)).to.equal(WAD)

      expect(await ladle.exitEther(ethVaultId, ethId, owner))
        .to.emit(weth, 'Withdrawal')
        .withArgs(ladle.address, WAD)
      expect(await weth.balanceOf(ladle.address)).to.equal(0)
    })

    it('users can pour then unwrap to ETH in a single transaction with batch', async () => {
      const pourData = ethers.utils.defaultAbiCoder.encode(
        ['address', 'int128', 'int128'],
        [ladle.address, WAD.mul(-1), 0]
      )
      const exitEtherData = ethers.utils.defaultAbiCoder.encode(['bytes6', 'address'], [ethId, owner])

      await ladle.batch(ethVaultId, [OPS.POUR, OPS.EXIT_ETHER], [pourData, exitEtherData])
    })
  })

  describe('with ETH posted and positive debt', async () => {
    beforeEach(async () => {
      expect(await ladle.joinEther(ethVaultId, ethId, { value: WAD }))
      await ladle.pour(ethVaultId, owner, WAD, WAD)
    })

    it('users can close to post ETH', async () => {
      expect(await ladle.joinEther(ethVaultId, ethId, { value: WAD }))
      expect(await ladle.close(ethVaultId, owner, WAD, WAD.mul(-1)))
        .to.emit(cauldron, 'VaultPoured')
        .withArgs(ethVaultId, seriesId, ethId, WAD, WAD.mul(-1))
      expect(await weth.balanceOf(wethJoin.address)).to.equal(WAD.mul(2))
      expect((await cauldron.balances(ethVaultId)).ink).to.equal(WAD.mul(2))
    })
  })
})
