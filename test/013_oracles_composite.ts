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
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { CompositeMultiOracle } from '../typechain/CompositeMultiOracle'
import { ChainlinkAggregatorV3Mock } from '../typechain/ChainlinkAggregatorV3Mock'
import { DAIMock } from '../typechain/DAIMock'
import { USDCMock } from '../typechain/USDCMock'
import { WETH9Mock } from '../typechain/WETH9Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle
import { BigNumber } from '@ethersproject/bignumber'

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

  let chainlinkMultiOracle: ChainlinkMultiOracle
  let compositeMultiOracle: CompositeMultiOracle

  let daiEthAggregator: ChainlinkAggregatorV3Mock
  let usdcEthAggregator: ChainlinkAggregatorV3Mock

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
  })

  it('setSource() sets source both ways', async () => {
    const quoteId = DAI
    const baseId = ETH
    const source = chainlinkMultiOracle.address
    expect(await compositeMultiOracle.sources(baseId, quoteId)).to.equal('0x0000000000000000000000000000000000000000')
    expect(await compositeMultiOracle.setSource(baseId, quoteId, source))
      .to.emit(compositeMultiOracle, 'SourceSet')
      .withArgs(quoteId, baseId, source)
    expect(await compositeMultiOracle.sources(baseId, quoteId)).to.equal(source)
    expect(await compositeMultiOracle.sources(quoteId, baseId)).to.equal(source)
  })

  it('setPaths() sets path and reverse path', async () => {
    const quoteId = DAI
    const baseId = ETH
    const path = [USDC]
    const source = chainlinkMultiOracle.address
    await compositeMultiOracle.setSource(DAI, USDC, chainlinkMultiOracle.address)
    await compositeMultiOracle.setSource(ETH, USDC, chainlinkMultiOracle.address)
    expect(await compositeMultiOracle.setPath(baseId, quoteId, path)).to.emit(compositeMultiOracle, 'PathSet')
    expect(await compositeMultiOracle.paths(baseId, quoteId, 0)).to.equal(path[0])
    expect(await compositeMultiOracle.paths(quoteId, baseId, 0)).to.equal(path[0])
  })

  describe('With sources and paths set', async () => {
    beforeEach(async () => {
      // Set up the CompositeMultiOracle to draw from the ChainlinkMultiOracle
      await compositeMultiOracle.setSource(DAI, ETH, chainlinkMultiOracle.address)
      await compositeMultiOracle.setSource(USDC, ETH, chainlinkMultiOracle.address)
      await compositeMultiOracle.setPath(DAI, USDC, [ETH])
    })

    it('retrieves the value at spot price and gets updateTime for direct pairs', async () => {
      expect((await compositeMultiOracle.peek(bytes6ToBytes32(DAI), bytes6ToBytes32(ETH), WAD))[0]).to.equal(
        WAD.div(2500)
      )
      const [price, updateTime] = await compositeMultiOracle.peek(bytes6ToBytes32(DAI), bytes6ToBytes32(ETH), WAD)
      expect(updateTime.gt(BigNumber.from('0'))).to.be.true
      expect(updateTime.lt(BigNumber.from('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'))).to.be
        .true
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

    it('reverts on timestamp greater than current block', async () => {
      await daiEthAggregator.setTimestamp(
        BigNumber.from('0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff')
      )
      await expect(compositeMultiOracle.peek(bytes6ToBytes32(DAI), bytes6ToBytes32(ETH), WAD)).to.be.revertedWith(
        'Invalid updateTime'
      )
    })

    it('uses the oldest timestamp found', async () => {
      const { timestamp } = await ethers.provider.getBlock('latest')
      const one = BigNumber.from('0x1')
      await daiEthAggregator.setTimestamp(one)
      await usdcEthAggregator.setTimestamp(timestamp)
      expect((await compositeMultiOracle.peek(bytes6ToBytes32(DAI), bytes6ToBytes32(USDC), WAD))[1]).to.equal(one)
    })

    it('retrieves the value at spot price for DAI -> USDC and reverse', async () => {
      expect((await compositeMultiOracle.peek(bytes6ToBytes32(DAI), bytes6ToBytes32(USDC), WAD))[0]).to.equal(oneUSDC)
      expect((await compositeMultiOracle.peek(bytes6ToBytes32(USDC), bytes6ToBytes32(DAI), oneUSDC))[0]).to.equal(WAD)
    })
  })
})
