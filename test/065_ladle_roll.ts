import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants } from '@yield-protocol/utils-v2'
const { WAD, MAX128 } = constants
const MAX = MAX128
import { ETH } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'

describe('Ladle - roll', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let fyToken: FYToken
  let otherFYToken: FYToken
  let base: ERC20Mock
  let ladle: LadleWrapper
  let ladleFromOther: LadleWrapper
  const loan = '2' // Flash loan size relative to debt

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId, otherSeriesId])
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
  const otherSeriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  let vaultId: string
  let baseVaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    ladleFromOther = ladle.connect(otherAcc)
    base = env.assets.get(baseId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken
    otherFYToken = env.series.get(otherSeriesId) as FYToken

    // ==== Set testing environment ====
    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
    await ladle.pour(vaultId, owner, WAD, WAD)

    baseVaultId = (env.vaults.get(seriesId) as Map<string, string>).get(baseId) as string
    await ladle.pour(baseVaultId, owner, WAD, WAD)
  })

  it('does not allow rolling vaults other than to the vault owner', async () => {
    await expect(ladleFromOther.roll(vaultId, seriesId, loan, WAD)).to.be.revertedWith('Only vault owner')
  })

  it('rolls a vault', async () => {
    expect(await ladle.roll(vaultId, otherSeriesId, loan, MAX))
      .to.emit(cauldron, 'VaultRolled')
      .withArgs(vaultId, otherSeriesId, WAD.mul(105).div(100)) // Mock pools have a constant rate of 5%
    expect((await cauldron.vaults(vaultId)).seriesId).to.equal(otherSeriesId)
    expect((await cauldron.balances(vaultId)).ink).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).art).to.equal(WAD.mul(105).div(100))
  })

  it('borrowing fees are applied when rolling', async () => {
    const fee = WAD.div(1000000000) // 0.000000 001% wei/second
    await ladle.setFee(fee)
    await ladle.roll(vaultId, otherSeriesId, loan, MAX)
    const { timestamp } = await ethers.provider.getBlock('latest')
    const preFeeDebt = WAD.mul(105).div(100)
    const appliedFee = (await otherFYToken.maturity()).sub(timestamp).mul(preFeeDebt).mul(fee).div(WAD)

    expect(await fyToken.balanceOf(owner)).to.equal(WAD.mul(2))
    expect((await cauldron.balances(vaultId)).art).to.equal(preFeeDebt.add(appliedFee))
  })

  it('except if base == ilk', async () => {
    await ladle.pour(baseVaultId, owner, WAD.mul(5).div(100), 0) // The exchange rate is 1:1, but YieldSpace charges a 5%

    const fee = WAD.div(1000000000) // 0.000000 001% wei/second
    await ladle.setFee(fee)
    await ladle.roll(baseVaultId, otherSeriesId, loan, MAX)
    const preFeeDebt = WAD.mul(105).div(100)

    expect(await fyToken.balanceOf(owner)).to.equal(WAD.mul(2))
    expect((await cauldron.balances(baseVaultId)).art).to.equal(preFeeDebt)
  })

  describe('after maturity', async () => {
    beforeEach(async () => {
      await ethers.provider.send('evm_mine', [(await fyToken.maturity()).toNumber()])
    })

    it('rolls a vault', async () => {
      expect(await ladle.roll(vaultId, otherSeriesId, loan, MAX))
        .to.emit(cauldron, 'VaultRolled')
        .withArgs(vaultId, otherSeriesId, WAD.mul(105).div(100)) // Mock pools have a constant rate of 5%
      expect((await cauldron.vaults(vaultId)).seriesId).to.equal(otherSeriesId)
      expect((await cauldron.balances(vaultId)).ink).to.equal(WAD)
      expect((await cauldron.balances(vaultId)).art).to.equal(WAD.mul(105).div(100))
    })
  })
})
