import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id, constants } from '@yield-protocol/utils-v2'
const { WAD, MAX256 } = constants

import ERC1155MockArtifact from '../artifacts/contracts/other/notional/ERC1155Mock.sol/ERC1155Mock.json'
import Transfer1155ModuleArtifact from '../artifacts/contracts/other/notional/Transfer1155Module.sol/Transfer1155Module.json'

import { ERC1155Mock } from '../typechain/ERC1155Mock'
import { Cauldron } from '../typechain/Cauldron'
import { Transfer1155Module } from '../typechain/Transfer1155Module'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'

describe('Ladle - module', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let ladle: LadleWrapper
  let token: ERC1155Mock
  let transferModule: Transfer1155Module
  const tokenId = 1

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [], [])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
    other = await signers[1].getAddress()
  })

  const zeroAddress = '0x' + '0'.repeat(40)

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle

    // ==== Set ERC1155 token ====
    token = (await deployContract(ownerAcc, ERC1155MockArtifact)) as ERC1155Mock
    await token.mint(owner, tokenId, WAD.mul(100), '0x00')

    // ==== Set Transfer Module ====
    transferModule = (await deployContract(ownerAcc, Transfer1155ModuleArtifact, [
      cauldron.address,
      zeroAddress,
    ])) as Transfer1155Module
    await ladle.grantRoles([id(ladle.ladle.interface, 'addToken(address,bool)')], owner)
    await ladle.grantRoles([id(ladle.ladle.interface, 'addModule(address,bool)')], owner)

    await ladle.addModule(transferModule.address, true)
    await ladle.ladle.addToken(token.address, true)

    // Approve the Ladle to move the tokens
    await token.setApprovalForAll(ladle.address, true)
  })

  it('transfers ERC1155 through the ladle', async () => {
    const calldata = transferModule.interface.encodeFunctionData('transfer1155', [
      token.address,
      tokenId,
      other,
      WAD,
      '0x00',
    ])
    await ladle.moduleCall(transferModule.address, calldata)
    expect(await token.balanceOf(other, tokenId)).to.equal(WAD)
  })

  it('attempting to transfer an unregistered token reverts', async () => {
    const calldata = transferModule.interface.encodeFunctionData('transfer1155', [
      ladle.address,
      tokenId,
      other,
      WAD,
      '0x00',
    ])
    await expect(ladle.moduleCall(transferModule.address, calldata)).to.be.revertedWith('Unknown token')
  })
})
