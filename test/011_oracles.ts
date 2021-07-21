import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { CHI, RATE } from '../src/constants'

import { sendStatic } from './shared/helpers'

import { Contract } from '@ethersproject/contracts'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import OracleArtifact from '../artifacts/contracts/mocks/oracles/OracleMock.sol/OracleMock.json'
import ChainlinkMultiOracleArtifact from '../artifacts/contracts/oracles/chainlink/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import CompoundMultiOracleArtifact from '../artifacts/contracts/oracles/compound/CompoundMultiOracle.sol/CompoundMultiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import CTokenChiMockArtifact from '../artifacts/contracts/mocks/oracles/compound/CTokenChiMock.sol/CTokenChiMock.json'
import CTokenRateMockArtifact from '../artifacts/contracts/mocks/oracles/compound/CTokenRateMock.sol/CTokenRateMock.json'
import UniswapV3FactoryMockArtifact from '../artifacts/contracts/mocks/oracles/uniswap/UniswapV3FactoryMock.sol/UniswapV3FactoryMock.json'
import UniswapV3OracleArtifact from '../artifacts/contracts/oracles/uniswap/UniswapV3Oracle.sol/UniswapV3Oracle.json'

import { IOracle } from '../typechain/IOracle'
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { CompoundMultiOracle } from '../typechain/CompoundMultiOracle'
import { ChainlinkAggregatorV3Mock } from '../typechain/ChainlinkAggregatorV3Mock'
import { CTokenChiMock } from '../typechain/CTokenChiMock'
import { CTokenRateMock } from '../typechain/CTokenRateMock'
import { UniswapV3FactoryMock } from '../typechain/UniswapV3FactoryMock'
import { UniswapV3PoolMock } from '../typechain/UniswapV3PoolMock'
import { UniswapV3Oracle } from '../typechain/UniswapV3Oracle'

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
  let uniswapV3Factory: UniswapV3FactoryMock
  let uniswapV3Pool: UniswapV3PoolMock
  let uniswapV3PoolAddress: string
  let uniswapV3Oracle: UniswapV3Oracle

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const usdQuoteId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ethQuoteId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockBytes6 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
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
    chainlinkMultiOracle.grantRole(id('setSources(bytes6[],bytes6[],address[])'), owner)
    await chainlinkMultiOracle.setSources([baseId], [usdQuoteId], [usdAggregator.address])
    await chainlinkMultiOracle.setSources([baseId], [ethQuoteId], [ethAggregator.address])

    cTokenChi = (await deployContract(ownerAcc, CTokenChiMockArtifact, [])) as CTokenChiMock
    cTokenRate = (await deployContract(ownerAcc, CTokenRateMockArtifact, [])) as CTokenRateMock

    compoundMultiOracle = (await deployContract(ownerAcc, CompoundMultiOracleArtifact, [])) as CompoundMultiOracle
    compoundMultiOracle.grantRole(id('setSources(bytes6[],bytes6[],address[])'), owner)
    await compoundMultiOracle.setSources([baseId, baseId], [CHI, RATE], [cTokenChi.address, cTokenRate.address])

    uniswapV3Factory = (await deployContract(ownerAcc, UniswapV3FactoryMockArtifact, [])) as UniswapV3FactoryMock
    const token0: string = ethers.utils.HDNode.fromSeed('0x0123456789abcdef0123456789abcdef').address
    const token1: string = ethers.utils.HDNode.fromSeed('0xfedcba9876543210fedcba9876543210').address
    uniswapV3PoolAddress = await sendStatic(uniswapV3Factory as Contract, 'createPool', ownerAcc, [token0, token1, 0])
    uniswapV3Pool = (await ethers.getContractAt('UniswapV3PoolMock', uniswapV3PoolAddress)) as UniswapV3PoolMock
    uniswapV3Oracle = (await deployContract(ownerAcc, UniswapV3OracleArtifact, [])) as UniswapV3Oracle
    uniswapV3Oracle.grantRole(id('setSources(bytes6[],bytes6[],address[])'), owner)
    await uniswapV3Oracle.setSources([baseId], [ethQuoteId], [uniswapV3PoolAddress])
  })

  it('sets and retrieves the value at spot price', async () => {
    await oracle.set(WAD.mul(2))
    expect((await oracle.callStatic.get(mockBytes32, mockBytes32, WAD))[0]).to.equal(WAD.mul(2))
  })

  it('revert on unknown sources', async () => {
    await expect(
      chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(mockBytes6), bytes6ToBytes32(mockBytes6), WAD)
    ).to.be.revertedWith('Source not found')
    await expect(
      compoundMultiOracle.callStatic.get(bytes6ToBytes32(mockBytes6), bytes6ToBytes32(CHI), WAD)
    ).to.be.revertedWith('Source not found')
    await expect(
      uniswapV3Oracle.callStatic.get(bytes6ToBytes32(mockBytes6), bytes6ToBytes32(mockBytes6), WAD)
    ).to.be.revertedWith('Source not found')
  })

  it('sets and retrieves the value at spot price from a chainlink multioracle', async () => {
    await usdAggregator.set(WAD.mul(2))
    await ethAggregator.set(WAD.mul(3))
    expect(
      (await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(usdQuoteId), WAD))[0]
    ).to.equal(WAD.mul(2))
    expect(
      (await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(usdQuoteId), bytes6ToBytes32(baseId), WAD))[0]
    ).to.equal(WAD.div(2))
    expect(
      (await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(ethQuoteId), WAD))[0]
    ).to.equal(WAD.mul(3))
    expect(
      (await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(ethQuoteId), bytes6ToBytes32(baseId), WAD))[0]
    ).to.equal(WAD.div(3))
  })

  it('sets and retrieves the chi and rate values at spot price from a compound multioracle', async () => {
    await cTokenChi.set(WAD.mul(2))
    await cTokenRate.set(WAD.mul(3))
    expect((await compoundMultiOracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(CHI), WAD))[0]).to.equal(
      WAD.mul(2)
    )
    expect((await compoundMultiOracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(RATE), WAD))[0]).to.equal(
      WAD.mul(3)
    )
  })

  it('retrieves the value at spot price from a uniswap v3 oracle', async () => {
    await uniswapV3Pool.set(WAD.mul(2))
    expect(
      (await uniswapV3Oracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(ethQuoteId), WAD))[0]
    ).to.equal(WAD.mul(2))
    expect(
      (await uniswapV3Oracle.callStatic.get(bytes6ToBytes32(ethQuoteId), bytes6ToBytes32(baseId), WAD))[0]
    ).to.equal(WAD.div(2))
  })
})
