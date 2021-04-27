import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import OracleArtifact from '../artifacts/contracts/mocks/OracleMock.sol/OracleMock.json'

import { OracleMock as Oracle } from '../typechain/OracleMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

describe('Oracle', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let oracle: Oracle

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    oracle = (await deployContract(ownerAcc, OracleArtifact, [])) as Oracle
  })

  it('sets and retrieves the spot price', async () => {
    await oracle.set(WAD.mul(2))
    expect((await oracle.callStatic.get(WAD))[0]).to.equal(WAD.mul(2))
  })
})
