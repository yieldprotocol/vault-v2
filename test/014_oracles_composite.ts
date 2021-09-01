import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import ChainlinkMultiOracleArtifact from '../artifacts/contracts/oracles/chainlink/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import CompositeMultiOracleArtifact from '../artifacts/contracts/oracles/composite/CompositeMultiOracle.sol/CompositeMultiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import DAIMockArtifact from '../artifacts/contracts/mocks/DAIMock.sol/DAIMock.json'
import USDCMockArtifact from '../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'
import WETH9MockArtifact from '../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'

import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { CompositeMultiOracle } from '../typechain/CompositeMultiOracle'
import { ChainlinkAggregatorV3Mock } from '../typechain/ChainlinkAggregatorV3Mock'
import { DAIMock } from '../typechain/DAIMock'
import { USDCMock } from '../typechain/USDCMock'
import { WETH9Mock } from '../typechain/WETH9Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracles - Composite', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let chainlinkMultiOracle: ChainlinkMultiOracle
  let compositeMultiOracle: CompositeMultiOracle
  let basePath1Aggregator: ChainlinkAggregatorV3Mock
  let path1Path2Aggregator: ChainlinkAggregatorV3Mock
  let path2IlkAggregator: ChainlinkAggregatorV3Mock
  let dai: DAIMock
  let usdc: USDCMock
  let weth: WETH9Mock

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
    // Deploy assets
    dai = (await deployContract(ownerAcc, DAIMockArtifact)) as DAIMock
    usdc = (await deployContract(ownerAcc, USDCMockArtifact)) as USDCMock
    weth = (await deployContract(ownerAcc, WETH9MockArtifact)) as WETH9Mock

    // Deploy oracles
    chainlinkMultiOracle = (await deployContract(ownerAcc, ChainlinkMultiOracleArtifact, [])) as ChainlinkMultiOracle
    chainlinkMultiOracle.grantRole(id('setSource(bytes6,address,bytes6,address,address)'), owner)
    compositeMultiOracle = (await deployContract(ownerAcc, CompositeMultiOracleArtifact, [])) as CompositeMultiOracle
    compositeMultiOracle.grantRoles(
      [id('setSource(bytes6,bytes6,address)'), id('setPath(bytes6,bytes6,bytes6[])')],
      owner
    )

    // Deploy original sources
    basePath1Aggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as ChainlinkAggregatorV3Mock
    path1Path2Aggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as ChainlinkAggregatorV3Mock
    path2IlkAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as ChainlinkAggregatorV3Mock

    // Set up the ChainlinkMultiOracle to draw from original sources
    await chainlinkMultiOracle.setSource(
      baseId,
      dai.address,
      path1Id,
      dai.address,
      basePath1Aggregator.address,
    )
    await chainlinkMultiOracle.setSource(
      path1Id,
      dai.address,
      path2Id,
      dai.address,
      path1Path2Aggregator.address,
    )
    await chainlinkMultiOracle.setSource(
      path2Id,
      dai.address,
      ilkId,
      weth.address,
      path2IlkAggregator.address
    )

    // Set up the CompositeMultiOracle to draw from the ChainlinkMultiOracle
    await compositeMultiOracle.setSource(
      baseId,
      path1Id,
      chainlinkMultiOracle.address,
    )
    await compositeMultiOracle.setSource(
      path1Id,
      path2Id,
      chainlinkMultiOracle.address,
    )
    await compositeMultiOracle.setSource(
      path2Id,
      ilkId,
      chainlinkMultiOracle.address
    )

    // Configure the base -> path1 -> path2 -> ilk path for base / ilk
    await compositeMultiOracle.setPath(baseId, ilkId, [path1Id, path2Id])

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

  it('retrieves the value at spot price for path1 -> base', async () => {
    expect((await compositeMultiOracle.peek(bytes6ToBytes32(path1Id), bytes6ToBytes32(baseId), WAD))[0]).to.equal(
      WAD.div(2)
    )
  })

  it('retrieves the value at spot price through the path', async () => {
    expect(
      (await compositeMultiOracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(ilkId), WAD))[0]
    ).to.equal(WAD.mul(30))
  })

  it('retrieves the value at spot price through the reverse path', async () => {
    expect(
      (await compositeMultiOracle.callStatic.get(bytes6ToBytes32(ilkId), bytes6ToBytes32(baseId), WAD.mul(3)))[0]
    ).to.equal(WAD.div(10))
  })
})
