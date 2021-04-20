import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id } from '@yield-protocol/utils'

import { constants } from '@yield-protocol/utils-v2'
const { WAD, MAX256 } = constants
const MAX = MAX256

import JoinArtifact from '../artifacts/contracts/Join.sol/Join.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'

import { Join } from '../typechain/Join'
import { ERC20Mock } from '../typechain/ERC20Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

describe('Join', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let otherAcc: SignerWithAddress
  let other: string
  let join: Join
  let joinFromOther: Join
  let token: ERC20Mock
  let otherToken: ERC20Mock

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  beforeEach(async () => {
    token = (await deployContract(ownerAcc, ERC20MockArtifact, ['MTK', 'Mock Token'])) as ERC20Mock
    otherToken = (await deployContract(ownerAcc, ERC20MockArtifact, ['OTH', 'Other Token'])) as ERC20Mock
    join = (await deployContract(ownerAcc, JoinArtifact, [token.address])) as Join
    joinFromOther = join.connect(otherAcc)

    await join.grantRoles(
      [id('join(address,uint128)'), id('exit(address,uint128)'), id('retrieve(address,address)')],
      owner
    )

    await token.mint(owner, WAD.mul(100))
    await token.approve(join.address, MAX)
  })

  it('retrieves airdropped tokens', async () => {
    await otherToken.mint(join.address, WAD)
    expect(await join.retrieve(otherToken.address, other))
      .to.emit(otherToken, 'Transfer')
      .withArgs(join.address, other, WAD)
  })

  it('pulls tokens from user', async () => {
    expect(await join.join(owner, WAD))
      .to.emit(token, 'Transfer')
      .withArgs(owner, join.address, WAD)
    expect(await join.storedBalance()).to.equal(WAD)
  })

  describe('with tokens in the join', async () => {
    beforeEach(async () => {
      await token.transfer(join.address, WAD)
    })

    it('accepts surplus as a transfer', async () => {
      expect(await join.join(owner, WAD)).to.not.emit(token, 'Transfer')
      expect(await join.storedBalance()).to.equal(WAD)
    })

    it('combines surplus and tokens pulled from the user', async () => {
      expect(await join.join(owner, WAD.mul(2)))
        .to.emit(token, 'Transfer')
        .withArgs(owner, join.address, WAD)
      expect(await join.storedBalance()).to.equal(WAD.mul(2))
    })

    it('the stored balance can be updated', async () => {
      expect(await join.join(owner, 0)).to.not.emit(token, 'Transfer')
      expect(await join.storedBalance()).to.equal(WAD)
    })

    describe('with a positive stored balance', async () => {
      beforeEach(async () => {
        await join.join(owner, 0)
      })

      it('pushes tokens to user', async () => {
        expect(await join.exit(owner, WAD))
          .to.emit(token, 'Transfer')
          .withArgs(join.address, owner, WAD)
        expect(await join.storedBalance()).to.equal(0)
      })
    })
  })
})
