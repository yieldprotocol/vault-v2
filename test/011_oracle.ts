import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import OracleArtifact from '../artifacts/contracts/mocks/OracleMock.sol/OracleMock.json'

import { OracleMock as Oracle } from '../typechain/OracleMock'
import { BigNumber } from 'ethers'

import { ethers, waffle } from 'hardhat'
// import { id } from '../src'
import { expect } from 'chai'
const { deployContract } = waffle
const timeMachine = require('ether-time-traveler');
const provider = ethers.provider;

describe('Oracle', () => {
  let snapshotId: any
  let ownerAcc: SignerWithAddress
  let owner: string
  let oracle: Oracle

  const pastMaturity = 1600000000
  const RAY = BigNumber.from("1000000000000000000000000000")

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    snapshotId = await timeMachine.takeSnapshot(provider);
    oracle = (await deployContract(ownerAcc, OracleArtifact, [])) as Oracle
  })

  afterEach(async() => {
    await timeMachine.revertToSnapshot(provider, snapshotId);
  });

  it.only('advances time', async () => {
    const before = (await (provider.getBlock("latest"))).timestamp as number
    console.log(`Before: ${await oracle.time()} | ${before}`)

    const leap = 1000000
    await timeMachine.advanceTimeAndBlock(provider, leap)
    expect((await (provider.getBlock("latest"))).timestamp).to.equal(before + leap)
    console.log(`After:  ${await oracle.time()} | ${before + leap}`)
  })

  it('sets and retrieves the spot price', async () => {
    await oracle.setSpot(1)
    expect(await oracle.spot()).to.equal(1)
  })

  describe('with a spot price', async () => {
    beforeEach(async () => {
      await oracle.setSpot(1)
    })

    it('records and retrieves the spot price', async () => {
      expect(await oracle.record(pastMaturity)).to.emit(oracle, 'SpotRecorded').withArgs(pastMaturity, 1)

      await oracle.setSpot(2) // Just to be sure we are retrieving the recorded value
      expect(await oracle.recorded(pastMaturity)).to.equal(1)
    })

    describe('with a recorded price', async () => {
      beforeEach(async () => {
        await oracle.record(pastMaturity)
      })
  
      it('retrieves the spot price accrual', async () => {
        await oracle.setSpot(2) // Just to be sure we are retrieving the recorded value
        expect(await oracle.accrual(pastMaturity)).to.equal(RAY.mul(2))
      })
    })
  })
})
