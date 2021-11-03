import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
import { parseEther } from '@ethersproject/units'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { USDC, ETH, DAI, WSTETH, STETH } from '../src/constants'

import { LidoOracle } from '../typechain/LidoOracle'
import { WstETHMock } from '../typechain/WstETHMock'
import { ChainlinkAggregatorV3Mock } from '../typechain/ChainlinkAggregatorV3Mock'
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { CompositeMultiOracle } from '../typechain/CompositeMultiOracle'
import { WETH9Mock } from '../typechain/WETH9Mock'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { USDCMock } from '../typechain/USDCMock'

import LidoOracleArtifact from '../artifacts/contracts/oracles/lido/LidoOracle.sol/LidoOracle.json'
import WstETHMockArtifact from '../artifacts/contracts/mocks/oracles/lido/WstETHMock.sol/WstETHMock.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import ChainlinkMultiOracleArtifact from '../artifacts/contracts/oracles/chainlink/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import CompositeMultiOracleArtifact from '../artifacts/contracts/oracles/composite/CompositeMultiOracle.sol/CompositeMultiOracle.json'
import WETH9MockArtifact from '../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import USDCMockArtifact from '../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'

const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracles - Lido', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let weth: WETH9Mock
  let steth: ERC20Mock
  let usdc: USDCMock
  let lidoOracle: LidoOracle
  let lidoMock: WstETHMock
  let chainlinkMultiOracle: ChainlinkMultiOracle
  let compositeMultiOracle: CompositeMultiOracle
  let stethEthAggregator: ChainlinkAggregatorV3Mock
  let usdcEthAggregator: ChainlinkAggregatorV3Mock
  const mockBytes6 = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
    lidoMock = (await deployContract(ownerAcc, WstETHMockArtifact)) as WstETHMock
    await lidoMock.set('1008339308050006006')

    weth = (await deployContract(ownerAcc, WETH9MockArtifact)) as WETH9Mock
    usdc = (await deployContract(ownerAcc, USDCMockArtifact)) as USDCMock
    steth = (await deployContract(ownerAcc, ERC20MockArtifact, ['Liquid staked Ether 2.0', 'stETH'])) as ERC20Mock

    chainlinkMultiOracle = (await deployContract(ownerAcc, ChainlinkMultiOracleArtifact, [])) as ChainlinkMultiOracle
    await chainlinkMultiOracle.grantRole(
      id(chainlinkMultiOracle.interface, 'setSource(bytes6,address,bytes6,address,address)'),
      owner
    )
    usdcEthAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as ChainlinkAggregatorV3Mock
    stethEthAggregator = (await deployContract(
      ownerAcc,
      ChainlinkAggregatorV3MockArtifact
    )) as ChainlinkAggregatorV3Mock

    //Set stETH/ETH chainlink oracle
    await chainlinkMultiOracle.setSource(STETH, steth.address, ETH, weth.address, stethEthAggregator.address)
    await chainlinkMultiOracle.setSource(USDC, usdc.address, ETH, weth.address, usdcEthAggregator.address)

    await stethEthAggregator.set('992415619690099500')
    await usdcEthAggregator.set(WAD.div(4000)) // 1 USDC (1^6) in ETH
    lidoOracle = (await deployContract(ownerAcc, LidoOracleArtifact, [
      bytes6ToBytes32(WSTETH),
      bytes6ToBytes32(STETH),
    ])) as LidoOracle
    await lidoOracle.grantRole(id(lidoOracle.interface, 'setSource(address)'), owner)
    await lidoOracle['setSource(address)'](lidoMock.address) //mockOracle

    compositeMultiOracle = (await deployContract(ownerAcc, CompositeMultiOracleArtifact)) as CompositeMultiOracle
    compositeMultiOracle.grantRoles(
      [
        id(compositeMultiOracle.interface, 'setSource(bytes6,bytes6,address)'),
        id(compositeMultiOracle.interface, 'setPath(bytes6,bytes6,bytes6[])'),
      ],
      owner
    )
    // Set up the CompositeMultiOracle to draw from the ChainlinkMultiOracle
    await compositeMultiOracle.setSource(WSTETH, STETH, lidoOracle.address)
    await compositeMultiOracle.setSource(STETH, ETH, chainlinkMultiOracle.address)
    await compositeMultiOracle.setSource(USDC, ETH, chainlinkMultiOracle.address)

    //Set path for wsteth-steth-eth
    await compositeMultiOracle.setPath(WSTETH, ETH, [STETH])

    // Set path for wsteth-steth-eth.USDC
    await compositeMultiOracle.setPath(WSTETH, USDC, [STETH, ETH])
  })

  it('sets and retrieves the value at spot price', async () => {
    expect((await lidoOracle.callStatic.get(bytes6ToBytes32(STETH), bytes6ToBytes32(WSTETH), WAD))[0]).to.equal(
      '991729660855795538'
    )
    expect(
      (await lidoOracle.callStatic.get(bytes6ToBytes32(WSTETH), bytes6ToBytes32(STETH), parseEther('1')))[0]
    ).to.equal('1008339308050006006')
  })

  it('revert on unknown sources', async () => {
    await expect(lidoOracle.callStatic.get(bytes6ToBytes32(DAI), bytes6ToBytes32(mockBytes6), WAD)).to.be.revertedWith(
      'Source not found'
    )
  })

  describe('Composite', () => {
    it('retrieves the value at spot price for direct pairs', async () => {
      // WSTETH-STETH
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(WSTETH), bytes6ToBytes32(STETH), parseEther('1')))[0]
      ).to.equal('1008339308050006006')
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(STETH), bytes6ToBytes32(WSTETH), parseEther('1')))[0]
      ).to.equal('991729660855795538')

      // STETH-ETH
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(STETH), bytes6ToBytes32(ETH), parseEther('1')))[0]
      ).to.equal('992415619690099500')
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(ETH), bytes6ToBytes32(STETH), parseEther('1')))[0]
      ).to.equal('1007642342743727538')

      // ETH-USDC
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(ETH), bytes6ToBytes32(USDC), parseEther('1')))[0]
      ).to.equal('4000000000')
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(USDC), bytes6ToBytes32(ETH), parseEther('1')))[0]
      ).to.equal('250000000000000000000000000')
    })

    it('retrieves the value at spot price for WSTETH -> ETH and reverse', async () => {
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(WSTETH), bytes6ToBytes32(ETH), parseEther('1')))[0]
      ).to.equal('1000691679256332845')

      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(ETH), bytes6ToBytes32(WSTETH), parseEther('1')))[0]
      ).to.equal('999308798833176199')
    })

    it('retrieves the value at spot price for WSTETH -> USDC and reverse', async () => {
      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(WSTETH), bytes6ToBytes32(USDC), parseEther('1')))[0]
      ).to.equal('4002766717')

      expect(
        (await compositeMultiOracle.peek(bytes6ToBytes32(USDC), bytes6ToBytes32(WSTETH), parseEther('1')))[0]
      ).to.equal('249827199708294049841946834')
    })
  })
})
