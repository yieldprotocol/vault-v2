import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import OracleMockArtifact from '../artifacts/contracts/mocks/OracleMock.sol/OracleMock.json'
import JoinArtifact from '../artifacts/contracts/Join.sol/Join.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'

import { Vat } from '../typechain/Vat'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { OracleMock } from '../typechain/OracleMock'
import { CDPProxy } from '../typechain/CDPProxy'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle
const timeMachine = require('ether-time-traveler');

import { YieldEnvironment, WAD, RAY, THREE_MONTHS } from './shared/fixtures'

describe('CDPProxy - close', () => {
  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let vat: Vat
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock
  let ilkJoin: Join
  let spotOracle: OracleMock
  let rateOracle: OracleMock
  let cdpProxy: CDPProxy
  let cdpProxyFromOther: CDPProxy

  const mockAssetId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockVaultId =  ethers.utils.hexlify(ethers.utils.randomBytes(12))
  const MAX = ethers.constants.MaxUint256

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

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  let vaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture);
    vat = env.vat
    cdpProxy = env.cdpProxy
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    ilkJoin = env.joins.get(ilkId) as Join
    fyToken = env.series.get(seriesId) as FYToken
    rateOracle = env.oracles.get(baseId) as OracleMock
    spotOracle = env.oracles.get(ilkId) as OracleMock

    cdpProxyFromOther = cdpProxy.connect(otherAcc)

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
    cdpProxy.frob(vaultId, WAD, WAD)
  })

  it('does not allow to borrow', async () => {
    await expect(cdpProxy.close(mockVaultId, 0, WAD)).to.be.revertedWith('Only repay debt')
  })

  it('reverts on unknown vaults', async () => {
    await expect(cdpProxy.close(mockVaultId, 0, WAD.mul(-1))).to.be.revertedWith('Only vault owner')
  })

  it('does not allow adding a join before adding its ilk', async () => {
    await expect(cdpProxyFromOther.close(vaultId, 0, WAD.mul(-1))).to.be.revertedWith('Only vault owner')
  })

  it('users can repay their debt with underlying at a 1:1 rate', async () => {
    const baseBefore = await base.balanceOf(owner)
    await expect(cdpProxy.close(vaultId, 0, WAD.mul(-1))).to.emit(vat, 'VaultFrobbed').withArgs(vaultId, seriesId, ilkId, 0, WAD.mul(-1))
    expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD))
    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
    expect((await vat.vaultBalances(vaultId)).art).to.equal(0)
  })

  it('users can repay their debt with underlying and add collateral at the same time', async () => {
    const baseBefore = await base.balanceOf(owner)
    await expect(cdpProxy.close(vaultId, WAD, WAD.mul(-1))).to.emit(vat, 'VaultFrobbed').withArgs(vaultId, seriesId, ilkId, WAD, WAD.mul(-1))
    expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD))
    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
    expect((await vat.vaultBalances(vaultId)).art).to.equal(0)
    expect(await ilk.balanceOf(ilkJoin.address)).to.equal(WAD.mul(2))
    expect((await vat.vaultBalances(vaultId)).ink).to.equal(WAD.mul(2))
  })

  it('users can repay their debt with underlying and remove collateral at the same time', async () => {
    const baseBefore = await base.balanceOf(owner)
    await expect(cdpProxy.close(vaultId, WAD.mul(-1), WAD.mul(-1))).to.emit(vat, 'VaultFrobbed').withArgs(vaultId, seriesId, ilkId, WAD.mul(-1), WAD.mul(-1))
    expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD))
    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
    expect((await vat.vaultBalances(vaultId)).art).to.equal(0)
    expect(await ilk.balanceOf(ilkJoin.address)).to.equal(0)
    expect((await vat.vaultBalances(vaultId)).ink).to.equal(0)
  })

  describe('after maturity', async () => {
    const accrual = RAY.mul(110).div(100) // accrual is 10% 

    beforeEach(async () => {
      await spotOracle.setSpot(RAY.mul(1))
      await rateOracle.setSpot(RAY.mul(1))
      await timeMachine.advanceTimeAndBlock(ethers.provider, THREE_MONTHS)
      await rateOracle.record(await fyToken.maturity())
      await rateOracle.setSpot(accrual) // Since spot was 1 when recorded at maturity, accrual is equal to the current spot
    })

    it('users can repay their debt with underlying at accrual rate', async () => {
      const baseBefore = await base.balanceOf(owner)
      await expect(cdpProxy.close(vaultId, 0, WAD.mul(-1))).to.emit(vat, 'VaultFrobbed').withArgs(vaultId, seriesId, ilkId, 0, WAD.mul(-1))
      expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD.mul(accrual).div(RAY)))
      expect(await fyToken.balanceOf(owner)).to.equal(WAD)
      expect((await vat.vaultBalances(vaultId)).art).to.equal(0)
    })
  })
})
