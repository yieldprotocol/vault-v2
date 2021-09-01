import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { CHI, RATE } from '../src/constants'

import { sendStatic } from './shared/helpers'

import { Contract } from '@ethersproject/contracts'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import OracleArtifact from '../artifacts/contracts/mocks/oracles/OracleMock.sol/OracleMock.json'
import ChainlinkMultiOracleArtifact from '../artifacts/contracts/oracles/chainlink/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import DAIMockArtifact from '../artifacts/contracts/mocks/DAIMock.sol/DAIMock.json'
import USDCMockArtifact from '../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'

import { IOracle } from '../typechain/IOracle'
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { ChainlinkAggregatorV3Mock } from '../typechain/ChainlinkAggregatorV3Mock'
import { DAIMock } from '../typechain/DAIMock'
import { USDCMock } from '../typechain/USDCMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracles - Chainlink', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let oracle: IOracle
  let chainlinkMultiOracle: ChainlinkMultiOracle
  let usdAggregator: ChainlinkAggregatorV3Mock
  let ethAggregator: ChainlinkAggregatorV3Mock
  let dai: DAIMock
  let usdc: USDCMock

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const usdcId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const cDaiId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const cUSDCId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
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

    dai = (await deployContract(ownerAcc, DAIMockArtifact)) as DAIMock
    usdc = (await deployContract(ownerAcc, USDCMockArtifact)) as USDCMock

    usdAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact, [
      8,
    ])) as ChainlinkAggregatorV3Mock
    ethAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact, [
      18,
    ])) as ChainlinkAggregatorV3Mock

    chainlinkMultiOracle = (await deployContract(ownerAcc, ChainlinkMultiOracleArtifact, [])) as ChainlinkMultiOracle
    await chainlinkMultiOracle.grantRole(id('setSource(bytes6,bytes6,address)'), owner)
    await chainlinkMultiOracle.setSource(baseId, usdQuoteId, usdAggregator.address)
    await chainlinkMultiOracle.setSource(baseId, ethQuoteId, ethAggregator.address)
  })

  it('sets and retrieves the value at spot price', async () => {
    await oracle.set(WAD.mul(2))
    expect((await oracle.callStatic.get(mockBytes32, mockBytes32, WAD))[0]).to.equal(WAD.mul(2))
  })

  it('revert on unknown sources', async () => {
    await expect(
      chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(mockBytes6), bytes6ToBytes32(mockBytes6), WAD)
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

    expect((await chainlinkMultiOracle.peek(bytes6ToBytes32(baseId), bytes6ToBytes32(ethQuoteId), WAD))[0]).to.equal(
      WAD.mul(3)
    )
    expect((await chainlinkMultiOracle.peek(bytes6ToBytes32(ethQuoteId), bytes6ToBytes32(baseId), WAD))[0]).to.equal(
      WAD.div(3)
    )
  })
})
