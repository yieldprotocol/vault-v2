import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { CHI, RATE } from '../src/constants'

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

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracle', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let oracle: IOracle
  let chainlinkMultiOracle: ChainlinkMultiOracle
  let compoundMultiOracle: CompoundMultiOracle
  let usdAggregator: ChainlinkAggregatorV3Mock
  let ethAggregator: ChainlinkAggregatorV3Mock
  let cTokenChi: CTokenChiMock
  let cTokenRate: CTokenRateMock

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const usdQuoteId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ethQuoteId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockBytes32 = ethers.utils.hexlify(ethers.utils.randomBytes(32))

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    oracle = (await deployContract(ownerAcc, OracleArtifact, [])) as IOracle

    usdAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact, [
      8,
    ])) as ChainlinkAggregatorV3Mock
    ethAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact, [
      18,
    ])) as ChainlinkAggregatorV3Mock

    chainlinkMultiOracle = (await deployContract(ownerAcc, ChainlinkMultiOracleArtifact, [])) as ChainlinkMultiOracle
    await chainlinkMultiOracle.setSources([baseId], [usdQuoteId], [usdAggregator.address])
    await chainlinkMultiOracle.setSources([baseId], [ethQuoteId], [ethAggregator.address])

    cTokenChi = (await deployContract(ownerAcc, CTokenChiMockArtifact, [])) as CTokenChiMock
    cTokenRate = (await deployContract(ownerAcc, CTokenRateMockArtifact, [])) as CTokenRateMock

    compoundMultiOracle = (await deployContract(ownerAcc, CompoundMultiOracleArtifact, [])) as CompoundMultiOracle
    await compoundMultiOracle.setSources([baseId, baseId], [CHI, RATE], [cTokenChi.address, cTokenRate.address])
  })

  it('sets and retrieves the value at spot price', async () => {
    await oracle.set(WAD.mul(2))
    expect((await oracle.callStatic.get(mockBytes32, mockBytes32, WAD))[0]).to.equal(WAD.mul(2))
  })

  it('sets and retrieves the value at spot price from a chainlink multioracle', async () => {
    await usdAggregator.set(WAD.mul(2))
    await ethAggregator.set(WAD.mul(3))
    expect(
      (await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(usdQuoteId), WAD))[0]
    ).to.equal(WAD.mul(2))
    expect(
      (await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(ethQuoteId), WAD))[0]
    ).to.equal(WAD.mul(3))
  })

  it('sets and retrieves the chi and rate values at spot price from a compound multioracle', async () => {
    await cTokenChi.set(WAD.mul(2))
    await cTokenRate.set(WAD.mul(3))
    expect((await compoundMultiOracle.callStatic.get(bytes6ToBytes32(baseId), CHI, WAD))[0]).to.equal(WAD.mul(2))
    expect((await compoundMultiOracle.callStatic.get(bytes6ToBytes32(baseId), RATE, WAD))[0]).to.equal(WAD.mul(3))
  })
})
