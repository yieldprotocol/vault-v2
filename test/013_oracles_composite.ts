import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { ETH, DAI, USDC, WSTETH, STETH } from '../src/constants'

import ChainlinkMultiOracleArtifact from '../artifacts/contracts/oracles/chainlink/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import CompositeMultiOracleArtifact from '../artifacts/contracts/oracles/composite/CompositeMultiOracle.sol/CompositeMultiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import DAIMockArtifact from '../artifacts/contracts/mocks/DAIMock.sol/DAIMock.json'
import USDCMockArtifact from '../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'
import WETH9MockArtifact from '../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import STETHMockArtifact from '../artifacts/contracts/mocks/STETHMock.sol/STETHMock.json'
import { LidoOracle } from '../typechain/LidoOracle'
import { LidoMock } from '../typechain/LidoMock'
import LidoOracleArtifact from '../artifacts/contracts/oracles/lido/LidoOracle.sol/LidoOracle.json'
import LidoMockArtifact from '../artifacts/contracts/mocks/oracles/lido/LidoMock.sol/LidoMock.json'
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { CompositeMultiOracle } from '../typechain/CompositeMultiOracle'
import { ChainlinkAggregatorV3Mock } from '../typechain/ChainlinkAggregatorV3Mock'
import { DAIMock } from '../typechain/DAIMock'
import { USDCMock } from '../typechain/USDCMock'
import { WETH9Mock } from '../typechain/WETH9Mock'
import { STETHMock } from '../typechain/STETHMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
import { parseEther } from '@ethersproject/units'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracles - Composite', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let dai: DAIMock
  let usdc: USDCMock
  let weth: WETH9Mock
  let steth: STETHMock
  let chainlinkMultiOracle: ChainlinkMultiOracle
  let compositeMultiOracle: CompositeMultiOracle
  let lidoOracle: LidoOracle
  let lidoMock: LidoMock
  let daiEthAggregator: ChainlinkAggregatorV3Mock
  let usdcEthAggregator: ChainlinkAggregatorV3Mock
  let stethEthAggregator: ChainlinkAggregatorV3Mock

  const oneUSDC = WAD.div(1000000000000)

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    dai = (await deployContract(ownerAcc, DAIMockArtifact)) as DAIMock
    usdc = (await deployContract(ownerAcc, USDCMockArtifact)) as USDCMock
    weth = (await deployContract(ownerAcc, WETH9MockArtifact)) as WETH9Mock
    steth = (await deployContract(ownerAcc, STETHMockArtifact)) as STETHMock

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

    compositeMultiOracle = (await deployContract(ownerAcc, CompositeMultiOracleArtifact)) as CompositeMultiOracle
    compositeMultiOracle.grantRoles(
      [
        id(compositeMultiOracle.interface, 'setSource(bytes6,bytes6,address)'),
        id(compositeMultiOracle.interface, 'setPath(bytes6,bytes6,bytes6[])'),
      ],
      owner
    )

    // Set up the CompositeMultiOracle to draw from the ChainlinkMultiOracle
    await compositeMultiOracle.setSource(DAI, ETH, chainlinkMultiOracle.address)
    await compositeMultiOracle.setSource(USDC, ETH, chainlinkMultiOracle.address)

    await compositeMultiOracle.setPath(DAI, USDC, [ETH])
  })

  it('retrieves the value at spot price for direct pairs', async () => {
    expect((await compositeMultiOracle.peek(bytes6ToBytes32(DAI), bytes6ToBytes32(ETH), WAD))[0]).to.equal(
      WAD.div(2500)
    )
    expect((await compositeMultiOracle.peek(bytes6ToBytes32(USDC), bytes6ToBytes32(ETH), oneUSDC))[0]).to.equal(
      WAD.div(2500)
    )
    expect((await compositeMultiOracle.peek(bytes6ToBytes32(ETH), bytes6ToBytes32(DAI), WAD))[0]).to.equal(
      WAD.mul(2500)
    )
    expect((await compositeMultiOracle.peek(bytes6ToBytes32(ETH), bytes6ToBytes32(USDC), WAD))[0]).to.equal(
      oneUSDC.mul(2500)
    )
  })

  it('retrieves the value at spot price for DAI -> USDC and reverse', async () => {
    expect((await compositeMultiOracle.peek(bytes6ToBytes32(DAI), bytes6ToBytes32(USDC), WAD))[0]).to.equal(oneUSDC)
    expect((await compositeMultiOracle.peek(bytes6ToBytes32(USDC), bytes6ToBytes32(DAI), oneUSDC))[0]).to.equal(WAD)
  })

  describe('Lido Oracle', () => {
    beforeEach(async () => {
      lidoMock = (await deployContract(ownerAcc, LidoMockArtifact)) as LidoMock
      lidoOracle = (await deployContract(ownerAcc, LidoOracleArtifact)) as LidoOracle
      await lidoOracle.grantRole(id(lidoOracle.interface, 'setSource(address)'), owner)
      await lidoOracle['setSource(address)'](lidoMock.address) //mockOracle
      await lidoMock.set('1008339308050006006')
      stethEthAggregator = (await deployContract(
        ownerAcc,
        ChainlinkAggregatorV3MockArtifact
      )) as ChainlinkAggregatorV3Mock

      //Set stETH/ETH chainlink oracle
      await chainlinkMultiOracle.setSource(STETH, steth.address, ETH, weth.address, stethEthAggregator.address)
      await stethEthAggregator.set(parseEther('1'))
      // Set up the CompositeMultiOracle to draw from the ChainlinkMultiOracle
      await compositeMultiOracle.setSource(WSTETH, STETH, lidoOracle.address)
      await compositeMultiOracle.setSource(STETH, ETH, chainlinkMultiOracle.address)

      //Set path for wsteth-steth-eth
      await compositeMultiOracle.setPath(WSTETH, ETH, [STETH])
    })

    it('retrieves the value at spot price for direct pairs', async () => {
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(WSTETH), bytes6ToBytes32(STETH), parseEther('1')))[0]
      ).to.equal('1008339308050006006')
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(STETH), bytes6ToBytes32(ETH), parseEther('1')))[0]
      ).to.equal(parseEther('1'))
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(STETH), bytes6ToBytes32(WSTETH), parseEther('1')))[0]
      ).to.equal('991729660855795538')
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(ETH), bytes6ToBytes32(STETH), parseEther('1')))[0]
      ).to.equal(parseEther('1'))
    })

    it('retrieves the value at spot price for WSTETH -> ETH and reverse', async () => {
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(WSTETH), bytes6ToBytes32(ETH), parseEther('1')))[0]
      ).to.equal('1008339308050006006')

      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(ETH), bytes6ToBytes32(WSTETH), parseEther('1')))[0]
      ).to.equal('991729660855795538')
    })
  })
})
