import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import JoinArtifact from '../artifacts/contracts/Join.sol/Join.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'

import { Join } from '../typechain/Join'
import { ERC20Mock } from '../typechain/ERC20Mock'

import { ethers, waffle } from 'hardhat'
// import { id } from '../src'
import { expect } from 'chai'
const { deployContract } = waffle

describe('Vat', () => {
  let ownerAcc: SignerWithAddress
  let owner: string
  let otherAcc: SignerWithAddress
  let other: string
  let join: Join
  let joinFromOther: Join
  let token: ERC20Mock

  const mockAddress =  ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))
  const emptyAddress =  ethers.utils.getAddress('0x0000000000000000000000000000000000000000')
  const MAX = ethers.constants.MaxUint256

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  beforeEach(async () => {
    token = (await deployContract(ownerAcc, ERC20MockArtifact, ["MTK", "Mock Token"])) as ERC20Mock
    join = (await deployContract(ownerAcc, JoinArtifact, [token.address])) as Join
    joinFromOther = join.connect(otherAcc)

    await token.mint(owner, 1);
    await token.approve(join.address, MAX)
  })

  it('pulls tokens from user', async () => {
    expect(await join.join(owner, 1)).to.emit(token, 'Transfer').withArgs(owner, join.address, 1)
  })

  describe('with tokens in the join', async () => {
    beforeEach(async () => {
      await join.join(owner, 1)
    })

    it('pushes tokens to user', async () => {
      expect(await join.join(owner, -1)).to.emit(token, 'Transfer').withArgs(join.address, owner, 1)
    })
  })
})
