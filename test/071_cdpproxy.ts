import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import VatArtifact from '../artifacts/contracts/Vat.sol/Vat.json'
import JoinArtifact from '../artifacts/contracts/Join.sol/Join.json'
import FYTokenArtifact from '../artifacts/contracts/FYToken.sol/FYToken.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import CDPProxyArtifact from '../artifacts/contracts/CDPProxy.sol/CDPProxy.json'

import { Vat } from '../typechain/Vat'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { CDPProxy } from '../typechain/CDPProxy'

import { ethers, waffle } from 'hardhat'
// import { id } from '../src'
import { expect } from 'chai'
const { deployContract } = waffle

import { YieldEnvironment } from './shared/fixtures'

describe('CDPProxy', () => {
  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let vat: Vat
  let join: Join
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock
  let cdpProxy: CDPProxy
  let cdpProxyFromOther: CDPProxy

  const mockAssetId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const emptyAssetId = '0x000000000000'
  const mockVaultId =  ethers.utils.hexlify(ethers.utils.randomBytes(12))
  const mockAddress =  ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))
  const emptyAddress =  ethers.utils.getAddress('0x0000000000000000000000000000000000000000')
  const MAX = ethers.constants.MaxUint256

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const maturity = 1640995199;
  let vaultId: string

  beforeEach(async () => {
    env = await YieldEnvironment.setup(ownerAcc, otherAcc)
    vat = env.vat
    cdpProxy = env.cdpProxy

    base = (await deployContract(ownerAcc, ERC20MockArtifact, [baseId, "Mock Base"])) as ERC20Mock
    ilk = (await deployContract(ownerAcc, ERC20MockArtifact, [ilkId, "Mock Ilk"])) as ERC20Mock
    fyToken = (await deployContract(ownerAcc, FYTokenArtifact, [base.address, mockAddress, maturity, seriesId, "Mock FYToken"])) as FYToken
    join = (await deployContract(ownerAcc, JoinArtifact, [ilk.address])) as Join

    cdpProxyFromOther = cdpProxy.connect(otherAcc)

    // ==== Set platform ====
    await vat.addAsset(baseId, base.address)
    await vat.addAsset(ilkId, ilk.address)
    await vat.addSeries(seriesId, baseId, fyToken.address)

    // ==== Set testing environment ====
    await vat.build(seriesId, ilkId)
    const event = (await vat.queryFilter(vat.filters.VaultBuilt(null, null, null, null)))[0]
    vaultId = event.args.vaultId

    await ilk.mint(owner, 1);
    await ilk.approve(join.address, MAX);
  })

  it('does not allow adding a join before adding its ilk', async () => {
    await expect(cdpProxy.addJoin(mockAssetId, join.address)).to.be.revertedWith('Asset not found')
  })

  it('adds a join', async () => {
    expect(await cdpProxy.addJoin(ilkId, join.address)).to.emit(cdpProxy, 'JoinAdded').withArgs(ilkId, join.address)
    expect(await cdpProxy.joins(ilkId)).to.equal(join.address)
  })

  describe('with a join added', async () => {
    beforeEach(async () => {
      await cdpProxy.addJoin(ilkId, join.address)
    })

    it('only the vault owner can manage its collateral', async () => {
      await expect(cdpProxyFromOther.frob(vaultId, 1, 0)).to.be.revertedWith('Only vault owner')
    })

    it('users can frob to post collateral', async () => {
      expect(await cdpProxy.frob(vaultId, 1, 0)).to.emit(vat, 'VaultFrobbed').withArgs(vaultId, seriesId, ilkId, 1, 0)
      expect(await ilk.balanceOf(join.address)).to.equal(1)
      expect((await vat.vaultBalances(vaultId)).ink).to.equal(1)
    })

    describe('with ink in the join', async () => {
      beforeEach(async () => {
        await cdpProxy.frob(vaultId, 1, 0)
      })
  
      it('users can frob to withdraw collateral', async () => {
        await expect(cdpProxy.frob(vaultId, -1, 0)).to.emit(vat, 'VaultFrobbed').withArgs(vaultId, seriesId, ilkId, -1, 0)
        expect(await ilk.balanceOf(join.address)).to.equal(0)
        expect((await vat.vaultBalances(vaultId)).ink).to.equal(0)
      })

      it('users can frob to borrow fyToken', async () => {
        await expect(cdpProxy.frob(vaultId, 0, 1)).to.emit(vat, 'VaultFrobbed').withArgs(vaultId, seriesId, ilkId, 0, 1)
        expect(await fyToken.balanceOf(owner)).to.equal(1)
        expect((await vat.vaultBalances(vaultId)).art).to.equal(1)
      })
    })

    it('users can frob to post collateral and borrow fyToken', async () => {
      await expect(cdpProxy.frob(vaultId, 1, 1)).to.emit(vat, 'VaultFrobbed').withArgs(vaultId, seriesId, ilkId, 1, 1)
      expect(await ilk.balanceOf(join.address)).to.equal(1)
      expect(await fyToken.balanceOf(owner)).to.equal(1)
      expect((await vat.vaultBalances(vaultId)).ink).to.equal(1)
      expect((await vat.vaultBalances(vaultId)).art).to.equal(1)
    })
  })
})
