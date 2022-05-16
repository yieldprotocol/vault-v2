import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants

import FlashBorrowerArtifact from '../artifacts/contracts/mocks/FlashBorrower.sol/FlashBorrower.json'
import GiverArtifact from '../artifacts/contracts/utils/Giver.sol/Giver.json'

import { FYToken } from '../typechain/FYToken'
import { Cauldron, FlashBorrower, Giver } from '../typechain'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'

describe('Giver', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let owner: string
  let ownerAcc2: SignerWithAddress
  let owner2: string
  let fyToken: FYToken
  let borrower: FlashBorrower
  let giver: Giver
  let cauldron: Cauldron
  const vaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12))
  const vaultId2 = ethers.utils.hexlify(ethers.utils.randomBytes(12))
  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
    ownerAcc2 = signers[1]
    owner2 = await ownerAcc2.getAddress()
    env = await loadFixture(fixture)
    fyToken = env.series.get(seriesId) as FYToken
    cauldron = env.cauldron
    borrower = (await deployContract(ownerAcc, FlashBorrowerArtifact, [fyToken.address])) as FlashBorrower
    giver = (await deployContract(ownerAcc, GiverArtifact, [env.cauldron.address])) as Giver
    await giver.grantRole(id(giver.interface, 'banIlk(bytes6,bool)'), owner)
    await cauldron.grantRole(id(cauldron.interface, 'give(bytes12,address)'), giver.address)

    await cauldron.build(owner, vaultId, seriesId, ilkId)
    await cauldron.build(owner2, vaultId2, seriesId, ilkId)
  })

  it('Can give a vault of asset which is not banned', async () => {
    expect(await giver.bannedIlks(ilkId)).to.be.false
    await giver.give(vaultId, owner2)
    const vaultData = await cauldron.vaults(vaultId)
    expect(vaultData['owner']).to.not.eq(owner)
  })

  it('Ban an asset', async () => {
    await giver.banIlk(ilkId, true)
    expect(await giver.bannedIlks(ilkId)).be.true
  })

  it('Cannot give a vault of banned asset', async () => {
    await expect(giver.connect(ownerAcc2).give(vaultId2, owner2)).to.be.revertedWith('ilk is banned')
  })

  it('Cannot give a vault that doesnt belong to the user', async () => {
    await expect(giver.give(vaultId, owner2)).to.be.revertedWith('msg.sender is not the owner')
  })

  it('Unban an asset', async () => {
    await giver.banIlk(ilkId, false)
    expect(await giver.bannedIlks(ilkId)).be.false
  })

  it('Can give a vault of asset which is not banned', async () => {
    expect(await giver.bannedIlks(ilkId)).to.be.false
    await giver.connect(ownerAcc2).give(vaultId, owner)
    const vaultData = await cauldron.vaults(vaultId)
    expect(vaultData['owner']).to.not.eq(owner2)
  })
})
