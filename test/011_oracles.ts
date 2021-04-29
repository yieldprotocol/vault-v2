import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import OracleArtifact from '../artifacts/contracts/mocks/OracleMock.sol/OracleMock.json'
import ChainlinkMultiOracleArtifact from '../artifacts/contracts/oracles/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import CompoundMultiOracleArtifact from '../artifacts/contracts/oracles/CompoundMultiOracle.sol/CompoundMultiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import CTokenChiMockArtifact from '../artifacts/contracts/mocks/CTokenChiMock.sol/CTokenChiMock.json'
import CTokenRateMockArtifact from '../artifacts/contracts/mocks/CTokenRateMock.sol/CTokenRateMock.json'

import { IOracle } from '../typechain/IOracle'
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { CompoundMultiOracle } from '../typechain/CompoundMultiOracle'
import { ChainlinkAggregatorV3Mock } from '../typechain/ChainlinkAggregatorV3Mock'
import { CTokenChiMock } from '../typechain/CTokenChiMock'
import { CTokenRateMock } from '../typechain/CTokenRateMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

function bytes32ToBytes6(x: string): string {
  return x.slice(0, 14)
}

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

function bytes32ToAddress(x: string): string {
  return x.slice(0, 42)
}

function addressToBytes32(x: string): string {
  return x + '00'.repeat(12)
}

describe('Oracle', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let oracle: IOracle
  let chainlinkMultiOracle: ChainlinkMultiOracle
  let compoundMultiOracle: CompoundMultiOracle
  let aggregator: ChainlinkAggregatorV3Mock
  let cTokenChi: CTokenChiMock
  let cTokenRate: CTokenRateMock

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const quoteId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockBytes32 = ethers.utils.hexlify(ethers.utils.randomBytes(32))
  const baseAddress = ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))

  const CHI = ethers.utils.formatBytes32String('chi')
  const RATE = ethers.utils.formatBytes32String('rate')

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    oracle = (await deployContract(ownerAcc, OracleArtifact, [])) as IOracle

    aggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact, [])) as ChainlinkAggregatorV3Mock

    chainlinkMultiOracle = (await deployContract(ownerAcc, ChainlinkMultiOracleArtifact, [])) as ChainlinkMultiOracle
    await chainlinkMultiOracle.setSources([baseId], [quoteId], [aggregator.address])

    cTokenChi = (await deployContract(ownerAcc, CTokenChiMockArtifact, [])) as CTokenChiMock
    cTokenRate = (await deployContract(ownerAcc, CTokenRateMockArtifact, [])) as CTokenRateMock
    
    compoundMultiOracle = (await deployContract(ownerAcc, CompoundMultiOracleArtifact, [])) as CompoundMultiOracle
    await compoundMultiOracle.setSources([baseAddress, baseAddress], [CHI, RATE], [cTokenChi.address, cTokenRate.address])
  })

  it('sets and retrieves the value at spot price', async () => {
    await oracle.set(WAD.mul(2))
    expect((await oracle.callStatic.get(mockBytes32, mockBytes32, WAD))[0]).to.equal(WAD.mul(2))
  })

  it('sets and retrieves the value at spot price from a chainlink multioracle', async () => {
    await aggregator.set(WAD.mul(2))
    expect((await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(quoteId), WAD))[0]).to.equal(WAD.mul(2))
  })


  it.only('sets and retrieves the chi and rate values at spot price from a compound multioracle', async () => {
    await cTokenChi.set(WAD.mul(2))
    await cTokenRate.set(WAD.mul(3))
    expect((await compoundMultiOracle.callStatic.get(addressToBytes32(baseAddress), CHI, WAD))[0]).to.equal(WAD.mul(2))
    expect((await compoundMultiOracle.callStatic.get(addressToBytes32(baseAddress), RATE, WAD))[0]).to.equal(WAD.mul(3))
  })
})