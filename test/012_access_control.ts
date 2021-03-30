import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id } from '@yield-protocol/utils'

import RestrictedERC20MockArtifact from '../artifacts/contracts/mocks/RestrictedERC20Mock.sol/RestrictedERC20Mock.json'

import { RestrictedERC20Mock as Restricted } from '../typechain/RestrictedERC20Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

describe('Access Control', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let otherAcc: SignerWithAddress
  let other: string
  let restricted: Restricted
  let restrictedFromOther: Restricted

  const role = id('mint(address,uint256)')

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  beforeEach(async () => {
    restricted = (await deployContract(ownerAcc, RestrictedERC20MockArtifact, [
      'Restricted ERC20',
      'AUTH',
    ])) as Restricted
    restrictedFromOther = restricted.connect(otherAcc)
  })

  // access is denied if not granted
  // access is granted if granted
  // access can be revoked
  // access can be renounced
  // role can be locked

  it('access control is setup', async () => {
    expect(await restricted.hasRole('0x00000000', owner)).to.be.true
    expect(await restricted.hasRole('0x00000000', other)).to.be.false
    expect(await restricted.hasRole('0xffffffff', owner)).to.be.false
    expect(await restricted.getRoleAdmin('0xffffffff')).to.equal('0xffffffff')
  })

  it('access is denied if role not granted', async () => {
    await expect(restricted.mint(owner, 1)).to.be.revertedWith('Access denied')
  })

  it('access is granted if role granted', async () => {
    await expect(restricted.grantRole(role, owner)).to.emit(restricted, 'RoleGranted').withArgs(role, owner, owner)
    expect(await restricted.hasRole(role, owner)).to.be.true

    expect(await restricted.mint(owner, 1)).to.emit(restricted, 'Transfer')
    await expect(restricted.burn(owner, 1)).to.be.revertedWith('Access denied')
    await expect(restrictedFromOther.mint(owner, 1)).to.be.revertedWith('Access denied')
  })

  it('roles can be locked', async () => {
    await expect(restricted.lockRole(role)).to.emit(restricted, 'RoleAdminChanged').withArgs(role, '0xffffffff')
    await expect(restricted.grantRole(role, owner)).to.be.revertedWith('Only admin')
  })

  describe('with a granted role', async () => {
    beforeEach(async () => {
      await restricted.grantRole(role, other)
    })

    it('only admin can grant roles', async () => {
      await expect(restrictedFromOther.grantRole(role, owner)).to.be.revertedWith('Only admin')
    })

    it('roles can be revoked', async () => {
      await expect(restrictedFromOther.revokeRole(role, other)).to.be.revertedWith('Only admin')
      await expect(restricted.revokeRole(role, other)).to.emit(restricted, 'RoleRevoked').withArgs(role, other, owner)
      expect(await restricted.hasRole(role, other)).to.be.false
    })

    it('roles can be renounced', async () => {
      await expect(restricted.renounceRole(role, other)).to.be.revertedWith('Renounce only for self')
      await expect(restrictedFromOther.renounceRole(role, other))
        .to.emit(restricted, 'RoleRevoked')
        .withArgs(role, other, other)
      expect(await restricted.hasRole(role, other)).to.be.false
    })
  })
})
