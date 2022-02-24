import { constants, id } from '@yield-protocol/utils-v2'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

const { WAD, MAX256 } = constants

import Join1155Artifact from '../artifacts/contracts/other/notional/Join1155.sol/Join1155.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import ERC1155MockArtifact from '../artifacts/contracts/other/notional/ERC1155Mock.sol/ERC1155Mock.json'

import { Join1155 } from '../typechain/Join1155'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { ERC1155Mock } from '../typechain/ERC1155Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

describe('Join1155', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let otherAcc: SignerWithAddress
  let other: string
  let join: Join1155
  let token: ERC1155Mock
  let tokenId = '1'
  let otherERC20: ERC20Mock
  let otherERC1155: ERC1155Mock

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  beforeEach(async () => {
    token = (await deployContract(ownerAcc, ERC1155MockArtifact)) as ERC1155Mock
    otherERC20 = (await deployContract(ownerAcc, ERC20MockArtifact, ['', ''])) as ERC20Mock
    otherERC1155 = (await deployContract(ownerAcc, ERC1155MockArtifact)) as ERC1155Mock
    join = (await deployContract(ownerAcc, Join1155Artifact, [token.address, tokenId])) as Join1155

    await join.grantRoles(
      [
        id(join.interface, 'join(address,uint128)'),
        id(join.interface, 'exit(address,uint128)'),
        id(join.interface, 'retrieve(address,uint256,address)'),
        id(join.interface, 'retrieveERC20(address,address)'),
      ],
      owner
    )

    await token.mint(owner, tokenId, WAD.mul(100), '0x00')
    await token.setApprovalForAll(join.address, true)
  })

  it('retrieves airdropped ERC20 tokens', async () => {
    await otherERC20.mint(join.address, WAD)
    expect(await join.retrieveERC20(otherERC20.address, other))
      .to.emit(otherERC20, 'Transfer')
      .withArgs(join.address, other, WAD)
  })

  it('retrieves airdropped ERC1155 tokens', async () => {
    await otherERC1155.mint(join.address, tokenId, WAD, '0x00')
    expect(await join.retrieve(otherERC1155.address, tokenId, other))
      .to.emit(otherERC1155, 'TransferSingle')
      .withArgs(join.address, join.address, other, tokenId, WAD)
  })

  it('pulls tokens from user', async () => {
    expect(await join.join(owner, WAD))
      .to.emit(token, 'TransferSingle')
      .withArgs(join.address, owner, join.address, tokenId, WAD)
    expect(await join.storedBalance()).to.equal(WAD)
  })

  describe('with tokens in the join', async () => {
    beforeEach(async () => {
      await token.safeTransferFrom(owner, join.address, tokenId, WAD, '0x00')
    })

    it('accepts surplus as a transfer', async () => {
      expect(await join.join(owner, WAD)).to.not.emit(token, 'TransferSingle')
      expect(await join.storedBalance()).to.equal(WAD)
    })

    it('combines surplus and tokens pulled from the user', async () => {
      expect(await join.join(owner, WAD.mul(2)))
        .to.emit(token, 'TransferSingle')
        .withArgs(join.address, owner, join.address, tokenId, WAD)
      expect(await join.storedBalance()).to.equal(WAD.mul(2))
    })

    describe('with a positive stored balance', async () => {
      beforeEach(async () => {
        await join.join(owner, WAD)
      })

      it('pushes tokens to user', async () => {
        expect(await join.exit(owner, WAD))
          .to.emit(token, 'TransferSingle')
          .withArgs(join.address, join.address, owner, tokenId, WAD)
        expect(await join.storedBalance()).to.equal(0)
      })
    })
  })
})
