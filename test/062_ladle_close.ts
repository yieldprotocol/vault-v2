import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants

import { OPS } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { OracleMock } from '../typechain/OracleMock'
import { SourceMock } from '../typechain/SourceMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment, LadleWrapper } from './shared/fixtures'

describe('Ladle - close', function () {
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
  let spotOracle: OracleMock
  let spotSource: SourceMock
  let rateOracle: OracleMock
  let rateSource: SourceMock
  let ladle: LadleWrapper
  let ladleFromOther: LadleWrapper

  const mockVaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12))

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
  let vaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    ladleFromOther = ladle.connect(otherAcc)
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    ilkJoin = env.joins.get(ilkId) as Join
    fyToken = env.series.get(seriesId) as FYToken
    rateOracle = env.oracles.get('rate') as OracleMock
    rateSource = (await ethers.getContractAt('SourceMock', await rateOracle.source())) as SourceMock
    spotOracle = env.oracles.get(ilkId) as OracleMock
    spotSource = (await ethers.getContractAt('SourceMock', await spotOracle.source())) as SourceMock

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
    ladle.pour(vaultId, owner, WAD, WAD)
  })

  it('does not allow to borrow', async () => {
    await expect(ladle.close(vaultId, owner, 0, WAD)).to.be.revertedWith('Only repay debt')
  })

  it('reverts on unknown vaults', async () => {
    await expect(ladle.close(mockVaultId, owner, 0, WAD.mul(-1))).to.be.revertedWith('Only vault owner')
  })

  it('does not allow adding a join before adding its ilk', async () => {
    await expect(ladleFromOther.close(vaultId, other, 0, WAD.mul(-1))).to.be.revertedWith('Only vault owner')
  })

  it('users can repay their debt with underlying at a 1:1 rate', async () => {
    const baseBefore = await base.balanceOf(owner)
    await expect(ladle.close(vaultId, owner, 0, WAD.mul(-1)))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, 0, WAD.mul(-1))

    expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD))
    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).art).to.equal(0)
  })

  it('users can repay their debt with underlying and add collateral at the same time', async () => {
    const baseBefore = await base.balanceOf(owner)
    await expect(ladle.close(vaultId, owner, WAD, WAD.mul(-1)))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, WAD, WAD.mul(-1))

    expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD))
    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).art).to.equal(0)
    expect(await ilk.balanceOf(ilkJoin.address)).to.equal(WAD.mul(2))
    expect((await cauldron.balances(vaultId)).ink).to.equal(WAD.mul(2))
  })

  it('users can repay their debt with underlying and remove collateral at the same time', async () => {
    const baseBefore = await base.balanceOf(owner)
    await expect(ladle.close(vaultId, owner, WAD.mul(-1), WAD.mul(-1)))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, WAD.mul(-1), WAD.mul(-1))

    expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD))
    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).art).to.equal(0)
    expect(await ilk.balanceOf(ilkJoin.address)).to.equal(0)
    expect((await cauldron.balances(vaultId)).ink).to.equal(0)
  })

  it('users can repay their debt with underlying and remove collateral at the same time in a batch', async () => {
    const baseBefore = await base.balanceOf(owner)

    const closeData = ethers.utils.defaultAbiCoder.encode(
      ['address', 'int128', 'int128'],
      [owner, WAD.mul(-1), WAD.mul(-1)]
    )

    await expect(ladle.batch(vaultId, [OPS.CLOSE], [closeData]))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, WAD.mul(-1), WAD.mul(-1))

    expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD))
    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).art).to.equal(0)
    expect(await ilk.balanceOf(ilkJoin.address)).to.equal(0)
    expect((await cauldron.balances(vaultId)).ink).to.equal(0)
  })

  it('users can close and withdraw collateral to others', async () => {
    await expect(ladle.close(vaultId, other, WAD.mul(-1), WAD.mul(-1)))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, WAD.mul(-1), WAD.mul(-1))
    expect(await ilk.balanceOf(other)).to.equal(WAD)
  })

  describe('after maturity', async () => {
    const accrual = WAD.mul(110).div(100) // accrual is 10%

    beforeEach(async () => {
      await spotSource.set(WAD.mul(1))
      await rateSource.set(WAD.mul(1))
      await ethers.provider.send('evm_mine', [(await fyToken.maturity()).toNumber()])
      await cauldron.mature(seriesId)
      await rateSource.set(accrual) // Since spot was 1 when recorded at maturity, accrual is equal to the current spot
    })

    it('users can repay their debt with underlying at accrual rate', async () => {
      const baseBefore = await base.balanceOf(owner)
      await expect(ladle.close(vaultId, owner, 0, WAD.mul(-1)))
        .to.emit(cauldron, 'VaultPoured')
        .withArgs(vaultId, seriesId, ilkId, 0, WAD.mul(-1))
      expect(await base.balanceOf(owner)).to.equal(baseBefore.sub(WAD.mul(accrual).div(WAD)))
      expect(await fyToken.balanceOf(owner)).to.equal(WAD)
      expect((await cauldron.balances(vaultId)).art).to.equal(0)
    })
  })
})
