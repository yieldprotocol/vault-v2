import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import ChainlinkMultiOracleArtifact from '../artifacts/contracts/oracles/chainlink/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import CompositeMultiOracleArtifact from '../artifacts/contracts/oracles/composite/CompositeMultiOracle.sol/CompositeMultiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'

import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { CompositeMultiOracle } from '../typechain/CompositeMultiOracle'
import { ChainlinkAggregatorV3Mock } from '../typechain/ChainlinkAggregatorV3Mock'

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
  let chainlinkMultiOracle: ChainlinkMultiOracle
  let compositeMultiOracle: CompositeMultiOracle
  let basePath1Aggregator: ChainlinkAggregatorV3Mock
  let path1Path2Aggregator: ChainlinkAggregatorV3Mock
  let path2IlkAggregator: ChainlinkAggregatorV3Mock

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const path1Id = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const path2Id = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    // Deploy oracles
    chainlinkMultiOracle = (await deployContract(ownerAcc, ChainlinkMultiOracleArtifact, [])) as ChainlinkMultiOracle
    chainlinkMultiOracle.grantRole(id('setSources(bytes6[],bytes6[],address[])'), owner)
    compositeMultiOracle = (await deployContract(ownerAcc, CompositeMultiOracleArtifact, [])) as CompositeMultiOracle
    compositeMultiOracle.grantRoles(
      [id('setSources(bytes6[],bytes6[],address[])'), id('setPaths(bytes6[],bytes6[],bytes6[][])')],
      owner
    )

    // Deploy original sources
    basePath1Aggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact, [
      18,
    ])) as ChainlinkAggregatorV3Mock
    path1Path2Aggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact, [
      18,
    ])) as ChainlinkAggregatorV3Mock
    path2IlkAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact, [
      18,
    ])) as ChainlinkAggregatorV3Mock

    // Set up the ChainlinkMultiOracle to draw from original sources
    await chainlinkMultiOracle.setSources(
      [baseId, path1Id, path2Id],
      [path1Id, path2Id, ilkId],
      [basePath1Aggregator.address, path1Path2Aggregator.address, path2IlkAggregator.address]
    )

    // Set up the CompositeMultiOracle to draw from the ChainlinkMultiOracle
    await compositeMultiOracle.setSources(
      [baseId, path1Id, path2Id],
      [path1Id, path2Id, ilkId],
      [chainlinkMultiOracle.address, chainlinkMultiOracle.address, chainlinkMultiOracle.address]
    )

    // Configure the base -> path1 -> path2 -> ilk path for base / ilk
    await compositeMultiOracle.setPaths([baseId], [ilkId], [[path1Id, path2Id]])

    // Set price at source
    await basePath1Aggregator.set(WAD.mul(2))
    await path1Path2Aggregator.set(WAD.mul(3))
    await path2IlkAggregator.set(WAD.mul(5))
  })

  it('retrieves the value at spot price for base -> path1', async () => {
    expect((await compositeMultiOracle.peek(bytes6ToBytes32(baseId), bytes6ToBytes32(path1Id), WAD))[0]).to.equal(
      WAD.mul(2)
    )
  })

  it('retrieves the value at spot price through the path', async () => {
    expect(
      (await compositeMultiOracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(ilkId), WAD))[0]
    ).to.equal(WAD.mul(30))
  })
})
