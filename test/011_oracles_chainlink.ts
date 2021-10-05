import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { ETH, DAI, USDC } from '../src/constants'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import OracleArtifact from '../artifacts/contracts/mocks/oracles/OracleMock.sol/OracleMock.json'
import ChainlinkMultiOracleArtifact from '../artifacts/contracts/oracles/chainlink/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import DAIMockArtifact from '../artifacts/contracts/mocks/DAIMock.sol/DAIMock.json'
import USDCMockArtifact from '../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'
import WETH9MockArtifact from '../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'

import { IOracle } from '../typechain/IOracle'
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
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

describe('Oracles - Chainlink', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let oracle: IOracle
  let chainlinkMultiOracle: ChainlinkMultiOracle
  let daiEthAggregator: ChainlinkAggregatorV3Mock
  let usdcEthAggregator: ChainlinkAggregatorV3Mock
  let dai: DAIMock
  let usdc: USDCMock
  let weth: WETH9Mock

  const mockBytes6 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockBytes32 = ethers.utils.hexlify(ethers.utils.randomBytes(32))

  const oneUSDC = WAD.div(1000000000000)

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    oracle = (await deployContract(ownerAcc, OracleArtifact, [])) as IOracle

    dai = (await deployContract(ownerAcc, DAIMockArtifact)) as DAIMock
    usdc = (await deployContract(ownerAcc, USDCMockArtifact)) as USDCMock
    weth = (await deployContract(ownerAcc, WETH9MockArtifact)) as WETH9Mock

    daiEthAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as ChainlinkAggregatorV3Mock
    usdcEthAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as ChainlinkAggregatorV3Mock

    chainlinkMultiOracle = (await deployContract(ownerAcc, ChainlinkMultiOracleArtifact, [])) as ChainlinkMultiOracle
    await chainlinkMultiOracle.grantRole(
      id(chainlinkMultiOracle.interface, 'setSource(bytes6,address,bytes6,address,address)'),
      owner
    )
    await chainlinkMultiOracle.setSource(DAI, dai.address, ETH, weth.address, daiEthAggregator.address)
    await chainlinkMultiOracle.setSource(USDC, usdc.address, ETH, weth.address, usdcEthAggregator.address)

    await daiEthAggregator.set(WAD.div(2500)) // 1 DAI (1^18) in ETH
    await usdcEthAggregator.set(WAD.div(2500)) // 1 USDC (1^6) in ETH
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

  it('retrieves the value at spot price from a chainlink multioracle', async () => {
    expect(
      (await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(DAI), bytes6ToBytes32(ETH), WAD.mul(2500)))[0]
    ).to.equal(WAD)
    expect(
      (await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(USDC), bytes6ToBytes32(ETH), oneUSDC.mul(2500)))[0]
    ).to.equal(WAD)
    expect((await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(ETH), bytes6ToBytes32(DAI), WAD))[0]).to.equal(
      WAD.mul(2500)
    )
    expect((await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(ETH), bytes6ToBytes32(USDC), WAD))[0]).to.equal(
      oneUSDC.mul(2500)
    )
  })

  it('retrieves the value at spot price from a chainlink multioracle through ETH', async () => {
    expect(
      (await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(DAI), bytes6ToBytes32(USDC), WAD.mul(2500)))[0]
    ).to.equal(oneUSDC.mul(2500))
    expect(
      (await chainlinkMultiOracle.callStatic.get(bytes6ToBytes32(USDC), bytes6ToBytes32(DAI), oneUSDC.mul(2500)))[0]
    ).to.equal(WAD.mul(2500))
  })
})
