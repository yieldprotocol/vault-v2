import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { Cauldron } from '../typechain/Cauldron'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle
const timeMachine = require('ether-time-traveler')

import { YieldEnvironment, WAD, RAY, THREE_MONTHS } from './shared/fixtures'

describe('Ladle - vaults', function () {
  this.timeout(0)
  
  let snapshotId: any
  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let ladle: Ladle
  let ladleFromOther: Ladle

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId, otherIlkId], [seriesId, otherSeriesId])
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
    await timeMachine.revertToSnapshot(ethers.provider, snapshotId)
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const otherIlkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const otherSeriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const emptyAssetId = '0x000000000000'
  const emptyAddress = ethers.utils.getAddress('0x0000000000000000000000000000000000000000')

  let vaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle

    ladleFromOther = ladle.connect(otherAcc)

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
  })

  it('does not allow destroying vaults if not the vault owner', async () => {
    await expect(ladleFromOther.destroy(vaultId)).to.be.revertedWith('Only vault owner')
  })

  it('destroys a vault', async () => {
    expect(await ladle.destroy(vaultId))
      .to.emit(cauldron, 'VaultDestroyed')
      .withArgs(vaultId)
    const vault = await cauldron.vaults(vaultId)
    expect(vault.owner).to.equal(emptyAddress)
    expect(vault.seriesId).to.equal(emptyAssetId)
    expect(vault.ilkId).to.equal(emptyAssetId)
  })

  it('does not allow changing vaults if not the vault owner', async () => {
    await expect(ladleFromOther.tweak(vaultId, seriesId, ilkId)).to.be.revertedWith('Only vault owner')
  })

  it('changes a vault', async () => {
    expect(await ladle.tweak(vaultId, otherSeriesId, otherIlkId))
      .to.emit(cauldron, 'VaultTweaked')
      .withArgs(vaultId, otherSeriesId, otherIlkId)
    const vault = await cauldron.vaults(vaultId)
    expect(vault.owner).to.equal(owner)
    expect(vault.seriesId).to.equal(otherSeriesId)
    expect(vault.ilkId).to.equal(otherIlkId)
  })

  it('does not allow giving vaults if not the vault owner', async () => {
    await expect(ladleFromOther.give(vaultId, other)).to.be.revertedWith('Only vault owner')
  })

  it('gives a vault', async () => {
    expect(await ladle.give(vaultId, other))
      .to.emit(cauldron, 'VaultTransfer')
      .withArgs(vaultId, other)
    const vault = await cauldron.vaults(vaultId)
    expect(vault.owner).to.equal(other)
    expect(vault.seriesId).to.equal(seriesId)
    expect(vault.ilkId).to.equal(ilkId)
  })
})
