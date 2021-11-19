import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { CHI, RATE } from '../src/constants'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { ethers, waffle, artifacts, network } from 'hardhat'
import { expect } from 'chai'
import { AccumulatorMultiOracle } from '../typechain'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

// fast forward X seconds
async function ff(seconds: number) {
  await network.provider.send('evm_increaseTime', [seconds])
  await network.provider.send('evm_mine')
}

// make the next block's timestamp fast forward X seconds
async function ff_next_block(seconds: number) {
  const block = await ethers.provider.getBlock('latest')
  await network.provider.send('evm_setNextBlockTimestamp', [block.timestamp + seconds])
}

describe('AccumulatorMultiOracle', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let oracle: AccumulatorMultiOracle

  const baseId1 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const base1 = bytes6ToBytes32(baseId1)
  const baseId2 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const base2 = bytes6ToBytes32(baseId2)

  class Kind {
    static CHI = bytes6ToBytes32(CHI)
    static RATE = bytes6ToBytes32(RATE)
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    oracle = (await deployContract(
      ownerAcc,
      await artifacts.readArtifact('AccumulatorMultiOracle'),
      []
    )) as AccumulatorMultiOracle
    await oracle.grantRole(id(oracle.interface, 'setSource(bytes6,bytes6,uint256,uint256)'), owner)
    await oracle.grantRole(id(oracle.interface, 'updatePerSecondRate(bytes6,bytes6,uint256)'), owner)
  })

  it('setSource can be only called once', async () => {
    await oracle.setSource(baseId1, RATE, WAD, WAD)
    await expect(oracle.setSource(baseId1, RATE, WAD, WAD)).to.be.revertedWith('Source is already set')
  })

  describe('updatePerSecondRate', function () {
    it("can't be called on uninitialized source", async () => {
      await expect(oracle.updatePerSecondRate(baseId1, RATE, WAD)).to.be.revertedWith('Source not found')
    })
    it("can't be called on not-up-to-date source", async () => {
      await oracle.setSource(baseId1, RATE, WAD, WAD)
      await ff(100)
      await expect(oracle.updatePerSecondRate(baseId1, RATE, WAD)).to.be.revertedWith('stale accumulator')
    })
  })

  it('reverts on unknown sources', async () => {
    await oracle.setSource(baseId1, RATE, WAD, WAD)

    await expect(oracle.callStatic.peek(base2, Kind.RATE, WAD)).to.be.revertedWith('Source not found')

    await expect(oracle.callStatic.peek(base1, Kind.CHI, WAD)).to.be.revertedWith('Source not found')
  })

  it('does not mix up sources', async () => {
    await oracle.setSource(baseId1, RATE, WAD, WAD)
    await oracle.setSource(baseId1, CHI, WAD.mul(2), WAD)
    await oracle.setSource(baseId2, RATE, WAD.mul(3), WAD)
    await oracle.setSource(baseId2, CHI, WAD.mul(4), WAD)

    expect((await oracle.callStatic.peek(base1, Kind.RATE, WAD))[0]).to.be.equal(WAD.toString())

    expect((await oracle.callStatic.peek(base1, Kind.CHI, WAD))[0]).to.be.equal(WAD.mul(2).toString())

    expect((await oracle.callStatic.peek(base2, Kind.RATE, WAD))[0]).to.be.equal(WAD.mul(3).toString())

    expect((await oracle.callStatic.peek(base2, Kind.CHI, WAD))[0]).to.be.equal(WAD.mul(4).toString())
  })

  describe('get', () => {
    beforeEach(async () => {
      await oracle.setSource(baseId1, RATE, WAD, WAD.mul(2))
    })

    it('computes properly without checkpoints', async () => {
      expect((await oracle.callStatic.get(base1, Kind.RATE, WAD))[0]).to.be.equal(WAD.toString())

      await ff(10)
      expect((await oracle.callStatic.get(base1, Kind.RATE, WAD))[0]).to.be.equal(WAD.mul(1024).toString())

      await ff(2)
      expect((await oracle.callStatic.get(base1, Kind.RATE, WAD))[0]).to.be.equal(WAD.mul(4096).toString())
    })
    it('computes properly with checkpointing', async () => {
      await ff_next_block(1)
      await oracle.get(base1, Kind.RATE, WAD)
      expect((await oracle.callStatic.get(base1, Kind.RATE, WAD))[0]).to.be.equal(WAD.mul(2).toString())

      await ff_next_block(10)
      await oracle.get(base1, Kind.RATE, WAD)
      expect((await oracle.callStatic.get(base1, Kind.RATE, WAD))[0]).to.be.equal(WAD.mul(2048).toString())
    })

    it('updates peek()', async () => {
      await ff(10)
      expect((await oracle.peek(base1, Kind.RATE, WAD))[0]).to.be.equal(WAD) // 'get' was never called

      await ff_next_block(2)
      await oracle.get(base1, Kind.RATE, WAD)
      expect((await oracle.peek(base1, Kind.RATE, WAD))[0]).to.be.equal(WAD.mul(4096).toString())
    })
  })
})
