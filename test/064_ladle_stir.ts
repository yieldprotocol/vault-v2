import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { id, constants } from '@yield-protocol/utils-v2'
const { WAD } = constants

import StirModuleArtifact from '../artifacts/contracts/modules/StirModule.sol/StirModule.json'


import { ERC20Mock } from '../typechain/ERC20Mock'
import { Cauldron } from '../typechain/Cauldron'
import { FYToken } from '../typechain/FYToken'
import { StirModule } from '../typechain/StirModule'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'

describe('Ladle - stir', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let fyToken: FYToken
  let base: ERC20Mock
  let ladle: LadleWrapper
  let ladleFromOther: LadleWrapper
  let stirModule: StirModule

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId, otherIlkId], [seriesId])
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
  const vaultToId = ethers.utils.hexlify(ethers.utils.randomBytes(12))
  const otherIlkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  let vaultFromId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    ladleFromOther = ladle.connect(otherAcc)
    base = env.assets.get(baseId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken

    vaultFromId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string

    // ==== Set testing environment ====
    await ladle.build(vaultToId, seriesId, ilkId)

    // ==== Set stir module ====
    stirModule = (await deployContract(ownerAcc, StirModuleArtifact, [cauldron.address])) as StirModule
    await ladle.grantRoles(
      [
        id('setModule(address,bool)'),
      ],
      owner
    )

    await ladle.ladle.setModule(stirModule.address, true)
    await cauldron.grantRoles(
      [
        id('stir(bytes12,bytes12,uint128,uint128)'),
      ],
      stirModule.address
    )

    await stirModule.grantRoles(
      [
        id('stir(address,bytes)'),
      ],
      ladle.address
    )
  })

  it('does not allow moving collateral other than to the origin vault owner', async () => {
    await expect(ladleFromOther.stir(vaultFromId, vaultToId, WAD, 0)).to.be.revertedWith('Only origin vault owner')
  })

  it('does not allow moving debt other than to the destination vault owner', async () => {
    await expect(ladleFromOther.stir(vaultFromId, vaultToId, 0, WAD)).to.be.revertedWith('Only destination vault owner')
  })

  it('moves collateral', async () => {
    await ladle.pour(vaultFromId, owner, WAD, 0)
    expect(await ladle.stir(vaultFromId, vaultToId, WAD, 0))
      .to.emit(cauldron, 'VaultStirred')
      .withArgs(vaultFromId, vaultToId, WAD, 0)
    expect((await cauldron.balances(vaultFromId)).ink).to.equal(0)
    expect((await cauldron.balances(vaultToId)).ink).to.equal(WAD)
  })

  it('moves collateral through module', async () => {
    await ladle.pour(vaultFromId, owner, WAD, 0)

    const stirSelector = id('stir(address,bytes)')
    const stirData = ethers.utils.defaultAbiCoder.encode(
      ['bytes12', 'bytes12', 'uint128', 'uint128'],
      [vaultFromId, vaultToId, WAD, 0]
    )
    const moduleData = ethers.utils.defaultAbiCoder.encode(
      ['address', 'bytes4', 'bytes'],
      [stirModule.address, stirSelector, stirData]
    )
    expect(await ladle.ladle.batch([19], [moduleData]))
      .to.emit(cauldron, 'VaultStirred')
      .withArgs(vaultFromId, vaultToId, WAD, 0)
  })

  it('moves debt', async () => {
    await ladle.pour(vaultFromId, owner, WAD, WAD)
    await ladle.pour(vaultToId, owner, WAD, 0)
    expect(await ladle.stir(vaultFromId, vaultToId, 0, WAD))
      .to.emit(cauldron, 'VaultStirred')
      .withArgs(vaultFromId, vaultToId, 0, WAD)
    expect((await cauldron.balances(vaultFromId)).art).to.equal(0)
    expect((await cauldron.balances(vaultToId)).art).to.equal(WAD)
  })

  it('moves collateral and debt', async () => {
    await ladle.pour(vaultFromId, owner, WAD, WAD)
    expect(await ladle.stir(vaultFromId, vaultToId, WAD, WAD))
      .to.emit(cauldron, 'VaultStirred')
      .withArgs(vaultFromId, vaultToId, WAD, WAD)
    expect((await cauldron.balances(vaultFromId)).ink).to.equal(0)
    expect((await cauldron.balances(vaultToId)).ink).to.equal(WAD)
    expect((await cauldron.balances(vaultFromId)).art).to.equal(0)
    expect((await cauldron.balances(vaultToId)).art).to.equal(WAD)
  })

  it('moves collateral in a batch', async () => {
    await ladle.pour(vaultFromId, owner, WAD, 0)
    await ladle.give(vaultToId, other)

    expect(await ladle.batch([ladle.stirAction(vaultFromId, vaultToId, WAD, 0)]))
      .to.emit(cauldron, 'VaultStirred')
      .withArgs(vaultFromId, vaultToId, WAD, 0)
    expect((await cauldron.balances(vaultFromId)).ink).to.equal(0)
    expect((await cauldron.balances(vaultToId)).ink).to.equal(WAD)
  })

  it('moves debt in a batch', async () => {
    await ladle.pour(vaultFromId, owner, WAD, WAD)
    await ladle.pour(vaultToId, owner, WAD, 0)
    await ladle.give(vaultFromId, other)

    expect(await ladle.batch([ladle.stirAction(vaultFromId, vaultToId, 0, WAD)]))
      .to.emit(cauldron, 'VaultStirred')
      .withArgs(vaultFromId, vaultToId, 0, WAD)
    expect((await cauldron.balances(vaultFromId)).art).to.equal(0)
    expect((await cauldron.balances(vaultToId)).art).to.equal(WAD)
  })
})
