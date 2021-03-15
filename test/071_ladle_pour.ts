import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id } from '@yield-protocol/utils'

import OracleMockArtifact from '../artifacts/contracts/mocks/OracleMock.sol/OracleMock.json'
import JoinArtifact from '../artifacts/contracts/Join.sol/Join.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { OracleMock } from '../typechain/OracleMock'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

import { YieldEnvironment, WAD, RAY } from './shared/fixtures'

describe('Ladle - pour', () => {
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
  let oracle: OracleMock
  let ladle: Ladle
  let ladleFromOther: Ladle

  const mockAssetId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const MAX = ethers.constants.MaxUint256

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId], [seriesId])
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
  const vaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12))
  const ratio = 10000 // == 100% collateralization ratio

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken

    ladleFromOther = ladle.connect(otherAcc)

    // ==== Set testing environment ====
    // We add this asset manually, because `fixtures` would also add the join, which we want to test.
    ilk = (await deployContract(ownerAcc, ERC20MockArtifact, [ilkId, 'Mock Ilk'])) as ERC20Mock
    oracle = (await deployContract(ownerAcc, OracleMockArtifact, [])) as OracleMock
    await oracle.setSpot(RAY)

    await cauldron.addAsset(ilkId, ilk.address)
    await cauldron.setMaxDebt(baseId, ilkId, WAD.mul(2))
    await cauldron.setSpotOracle(baseId, ilkId, oracle.address, ratio)
    await cauldron.addIlks(seriesId, [ilkId])

    await cauldron.build(owner, vaultId, seriesId, ilkId)

    // Finally, we deploy the join. A check that a join exists would be impossible in `cauldron` functions.
    ilkJoin = (await deployContract(ownerAcc, JoinArtifact, [ilk.address])) as Join
    await ilkJoin.grantRoles([id('join(address,int128)')], ladle.address)

    await ilk.mint(owner, WAD.mul(10))
    await ilk.approve(ilkJoin.address, MAX)
  })

  it('does not allow adding a join before adding its ilk', async () => {
    await expect(ladle.addJoin(mockAssetId, ilkJoin.address)).to.be.revertedWith('Asset not found')
  })

  it('adds a join', async () => {
    expect(await ladle.addJoin(ilkId, ilkJoin.address))
      .to.emit(ladle, 'JoinAdded')
      .withArgs(ilkId, ilkJoin.address)
    expect(await ladle.joins(ilkId)).to.equal(ilkJoin.address)
  })

  describe('with a join added', async () => {
    beforeEach(async () => {
      await ladle.addJoin(ilkId, ilkJoin.address)
    })

    it('only one join per asset', async () => {
      await expect(ladle.addJoin(ilkId, ilkJoin.address)).to.be.revertedWith('One Join per Asset')
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
      })

      it('users can pour to withdraw collateral', async () => {
        await expect(ladle.pour(vaultId, owner, WAD.mul(-1), 0))
          .to.emit(cauldron, 'VaultPoured')
          .withArgs(vaultId, seriesId, ilkId, WAD.mul(-1), 0)
        expect(await ilk.balanceOf(ilkJoin.address)).to.equal(0)
        expect((await cauldron.balances(vaultId)).ink).to.equal(0)
      })

      it('users can pour to borrow fyToken', async () => {
        await expect(ladle.pour(vaultId, owner, 0, WAD))
          .to.emit(cauldron, 'VaultPoured')
          .withArgs(vaultId, seriesId, ilkId, 0, WAD)
        expect(await fyToken.balanceOf(owner)).to.equal(WAD)
        expect((await cauldron.balances(vaultId)).art).to.equal(WAD)
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

      it("users can't repay more debt than they have", async () => {
        await expect(ladle.pour(vaultId, owner, 0, WAD.mul(-2))).to.be.revertedWith('Result below zero')
      })

      it('users can borrow while under the global debt limit', async () => {
        await expect(ladle.pour(vaultId, owner, WAD, WAD))
          .to.emit(cauldron, 'VaultPoured')
          .withArgs(vaultId, seriesId, ilkId, WAD, WAD)
      })

      it("users can't borrow over the global debt limit", async () => {
        await expect(ladle.pour(vaultId, owner, WAD.mul(2), WAD.mul(2))).to.be.revertedWith('Max debt exceeded')
      })
    })
  })
})
