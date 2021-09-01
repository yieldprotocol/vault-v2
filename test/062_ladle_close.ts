import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { RATE, ETH } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { OracleMock } from '../typechain/OracleMock'
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { CompoundMultiOracle } from '../typechain/CompoundMultiOracle'
import { ISourceMock } from '../typechain/ISourceMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'

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
  let spotOracle: ChainlinkMultiOracle
  let spotSource: ISourceMock
  let rateOracle: CompoundMultiOracle
  let rateSource: ISourceMock
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

  after(async () => {
    await loadFixture(fixture) // We advance the time to test maturity features, this rolls it back after the tests
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ETH
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
    rateOracle = (env.oracles.get(RATE) as unknown) as CompoundMultiOracle
    rateSource = (await ethers.getContractAt('ISourceMock', await rateOracle.sources(baseId, RATE))) as ISourceMock
    spotOracle = (env.oracles.get(ilkId) as unknown) as ChainlinkMultiOracle
    spotSource = (await ethers.getContractAt(
      'ISourceMock',
      (await spotOracle.sources(baseId, ilkId))[0]
    )) as ISourceMock

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

    await expect(ladle.batch([ladle.closeAction(vaultId, owner, WAD.mul(-1), WAD.mul(-1))]))
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
