import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id } from '@yield-protocol/utils'
import { WAD, MAX256 as MAX } from './shared/constants'
import { BigNumber } from 'ethers'

import JoinArtifact from '../artifacts/contracts/Join.sol/Join.json'
import ERC20DecimalsMockArtifact from '../artifacts/contracts/mocks/ERC20DecimalsMock.sol/ERC20DecimalsMock.json'

import { Join } from '../typechain/Join'
import { ERC20DecimalsMock } from '../typechain/ERC20DecimalsMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

describe('Join', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let usdcJoin: Join
  let bigJoin: Join
  let usdc: ERC20DecimalsMock
  let big: ERC20DecimalsMock

  const oneUSDC = BigNumber.from(10).pow(6)
  const oneBIG = BigNumber.from(10).pow(24)

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    usdc = (await deployContract(ownerAcc, ERC20DecimalsMockArtifact, ['USDC', 'Mock Token', 6])) as ERC20DecimalsMock
    big = (await deployContract(ownerAcc, ERC20DecimalsMockArtifact, ['BIG', 'Mock Token', 24])) as ERC20DecimalsMock
    usdcJoin = (await deployContract(ownerAcc, JoinArtifact, [usdc.address])) as Join
    bigJoin = (await deployContract(ownerAcc, JoinArtifact, [big.address])) as Join

    await usdcJoin.grantRoles([id('join(address,uint128)'), id('exit(address,uint128)')], owner)
    await bigJoin.grantRoles([id('join(address,uint128)'), id('exit(address,uint128)')], owner)

    await usdc.mint(owner, oneUSDC.mul(100))
    await usdc.approve(usdcJoin.address, MAX)
    await big.mint(owner, oneBIG.mul(100))
    await big.approve(bigJoin.address, MAX)
  })

  it('pulls low decimal tokens from user', async () => {
    await usdc.approve(usdcJoin.address, MAX)
    expect(await usdcJoin.callStatic.join(owner, WAD)).to.equal(oneUSDC)

    await usdcJoin.join(owner, WAD)
    expect(await usdcJoin.storedBalance()).to.equal(oneUSDC)
  })

  it('joins transferred low decimal tokens', async () => {
    await usdc.transfer(usdcJoin.address, oneUSDC)
    expect(await usdcJoin.callStatic.join(owner, WAD)).to.equal(oneUSDC)

    await usdcJoin.join(owner, WAD)
    expect(await usdcJoin.storedBalance()).to.equal(oneUSDC)
  })

  it('pulls high decimal tokens from user', async () => {
    await big.approve(bigJoin.address, MAX)
    expect(await bigJoin.callStatic.join(owner, WAD)).to.equal(oneBIG)

    await bigJoin.join(owner, WAD)
    expect(await bigJoin.storedBalance()).to.equal(oneBIG)
  })

  it('joins transferred high decimal tokens', async () => {
    await big.transfer(bigJoin.address, oneBIG)
    expect(await bigJoin.callStatic.join(owner, WAD)).to.equal(oneBIG)

    await bigJoin.join(owner, WAD)
    expect(await bigJoin.storedBalance()).to.equal(oneBIG)
  })

  describe('with tokens in the join', async () => {
    beforeEach(async () => {
      await usdc.transfer(usdcJoin.address, oneUSDC)
      await usdcJoin.join(owner, WAD)
      await big.transfer(bigJoin.address, oneBIG)
      await bigJoin.join(owner, WAD)
    })

    it('pushes low decimal tokens to user', async () => {
      expect(await usdcJoin.callStatic.exit(owner, WAD)).to.equal(oneUSDC)
      await usdcJoin.exit(owner, WAD)
      expect(await usdcJoin.storedBalance()).to.equal(0)
    })

    it('pushes high decimal tokens to user', async () => {
      expect(await bigJoin.callStatic.exit(owner, WAD)).to.equal(oneBIG)
      await bigJoin.exit(owner, WAD)
      expect(await bigJoin.storedBalance()).to.equal(0)
    })
  })
})
