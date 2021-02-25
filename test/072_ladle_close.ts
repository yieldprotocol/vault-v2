import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { OracleMock } from '../typechain/OracleMock'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle
const timeMachine = require('ether-time-traveler');

import { YieldEnvironment, WAD, RAY, THREE_MONTHS } from './shared/fixtures'

describe('Ladle - close', () => {
  let snapshotId: any
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
  let spotOracle: OracleMock
  let rateOracle: OracleMock
  let ladle: Ladle
  let ladleFromOther: Ladle

  const mockVaultId =  ethers.utils.hexlify(ethers.utils.randomBytes(12))
  
  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    snapshotId = await timeMachine.takeSnapshot(ethers.provider)
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  after(async () => {
    await timeMachine.revertToSnapshot(ethers.provider, snapshotId);
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  let vaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture);
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    ilkJoin = env.joins.get(ilkId) as Join
    fyToken = env.series.get(seriesId) as FYToken
    rateOracle = env.oracles.get('rate') as OracleMock
    spotOracle = env.oracles.get(ilkId) as OracleMock

    ladleFromOther = ladle.connect(otherAcc)

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
    ladle.stir(vaultId, WAD, WAD)
  })

  it('does not allow to borrow', async () => {
    await expect(ladle.close(mockVaultId, 0, WAD)).to.be.revertedWith('Only repay debt')
  })

  it('reverts on unknown vaults', async () => {
    await expect(ladle.close(mockVaultId, 0, WAD.mul(-1))).to.be.revertedWith('Only vault owner')
  })

  it('does not allow adding a join before adding its ilk', async () => {
    await expect(ladleFromOther.close(vaultId, 0, WAD.mul(-1))).to.be.revertedWith('Only vault owner')
  })

  it('users can repay their debt with underlying at a 1:1 rate', async () => {
    const baseBefore = await base.balanceOf(owner)
    await expect(ladle.close(vaultId, 0, WAD.mul(-1))).to.emit(cauldron, 'VaultStirred').withArgs(vaultId, seriesId, ilkId, 0, WAD.mul(-1))
    expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD))
    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
    expect((await cauldron.vaultBalances(vaultId)).art).to.equal(0)
  })

  it('users can repay their debt with underlying and add collateral at the same time', async () => {
    const baseBefore = await base.balanceOf(owner)
    await expect(ladle.close(vaultId, WAD, WAD.mul(-1))).to.emit(cauldron, 'VaultStirred').withArgs(vaultId, seriesId, ilkId, WAD, WAD.mul(-1))
    expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD))
    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
    expect((await cauldron.vaultBalances(vaultId)).art).to.equal(0)
    expect(await ilk.balanceOf(ilkJoin.address)).to.equal(WAD.mul(2))
    expect((await cauldron.vaultBalances(vaultId)).ink).to.equal(WAD.mul(2))
  })

  it('users can repay their debt with underlying and remove collateral at the same time', async () => {
    const baseBefore = await base.balanceOf(owner)
    await expect(ladle.close(vaultId, WAD.mul(-1), WAD.mul(-1))).to.emit(cauldron, 'VaultStirred').withArgs(vaultId, seriesId, ilkId, WAD.mul(-1), WAD.mul(-1))
    expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD))
    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
    expect((await cauldron.vaultBalances(vaultId)).art).to.equal(0)
    expect(await ilk.balanceOf(ilkJoin.address)).to.equal(0)
    expect((await cauldron.vaultBalances(vaultId)).ink).to.equal(0)
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
      await expect(ladle.close(vaultId, 0, WAD.mul(-1))).to.emit(cauldron, 'VaultStirred').withArgs(vaultId, seriesId, ilkId, 0, WAD.mul(-1))
      expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD.mul(accrual).div(RAY)))
      expect(await fyToken.balanceOf(owner)).to.equal(WAD)
      expect((await cauldron.vaultBalances(vaultId)).art).to.equal(0)
    })
  })
})
