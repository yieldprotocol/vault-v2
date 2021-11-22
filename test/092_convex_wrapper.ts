import { ethers, waffle } from 'hardhat'
import * as fs from 'fs'
import { YieldEnvironment } from './shared/fixtures'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { expect } from 'chai'
import { ETH, DAI, USDC, CVX3CRV } from '../src/constants'
import {
  Ladle,
  ERC20Mock,
  WstETHMock,
  LidoWrapHandler,
  ConvexStakingWrapperYieldMock,
  ChainlinkMultiOracle,
  ISourceMock,
  Wand,
  Witch,
  CompositeMultiOracle,
  CurvePoolMock,
  DummyConvexCurveOracle,
  ChainlinkAggregatorV3Mock,
  WETH9Mock,
  DAIMock,
  USDCMock
} from '../typechain'

import ConvexStakingWrapperYieldMockArtifact from '../artifacts/contracts/mocks/ConvexStakingWrapperYieldMock.sol/ConvexStakingWrapperYieldMock.json'
import ChainlinkMultiOracleArtifact from '../artifacts/contracts/oracles/chainlink/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import DummyConvexCurveOracleArtifact from '../artifacts/contracts/oracles/convex/DummyConvexCurveOracle.sol/DummyConvexCurveOracle.json'
import CurvePoolMockArtifact from '../artifacts/contracts/mocks/oracles/convex/CurvePoolMock.sol/CurvePoolMock.json'
import CompositeMultiOracleArtifact from '../artifacts/contracts/oracles/composite/CompositeMultiOracle.sol/CompositeMultiOracle.json'
import WETH9MockArtifact from '../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import DAIMockArtifact from '../artifacts/contracts/mocks/DAIMock.sol/DAIMock.json'
import USDCMockArtifact from '../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { parseEther } from '@ethersproject/units'
import { LadleWrapper } from '../src/ladleWrapper'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
    return x + '00'.repeat(26)
  }

/**
 * @dev This script tests the stEth, wstEth and LidoWrapHandler integration with the Ladle
 */
describe('Convex Wrapper', function () {
  let wstEth: ERC20Mock
  let stEth: ERC20Mock
  let ladle: Ladle
  let wand: Wand
  let witch: Witch
  let ownerAcc: SignerWithAddress
  
  let convex: ConvexStakingWrapperYieldMock
  
  
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  let DummyConvexCurveOracle: DummyConvexCurveOracle
  let daiEthAggregator: ChainlinkAggregatorV3Mock
  let usdcEthAggregator: ChainlinkAggregatorV3Mock
  let usdtEthAggregator: ChainlinkAggregatorV3Mock
  let curvePool: CurvePoolMock

  let weth: WETH9Mock
  let dai: DAIMock
  let usdc: USDCMock

  let chainlinkMultiOracle: ChainlinkMultiOracle
  let compositeMultiOracle: CompositeMultiOracle
  

  let env: YieldEnvironment

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [USDC, ETH], [seriesId])
  }
  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]

    env = await fixture()
    convex = ((await deployContract(
      ownerAcc,
      ConvexStakingWrapperYieldMockArtifact
    )) as unknown) as ConvexStakingWrapperYieldMock
    
    ladle = env.ladle.ladle
    wand = env.wand
    witch = env.witch
    // const usdcSource = (await ethers.getContractAt(
    //   'ISourceMock',
    //   (await chainlinkMultiOracle.sources(USDC, ETH))[0]
    // )) as ISourceMock
    // await usdcSource.set("1") // ETH wei per USDC

    await ladle.grantRoles(
      [id(ladle.interface, 'addToken(address,bool)'), id(ladle.interface, 'addIntegration(address,bool)')],
      ownerAcc.address
    )

    weth = (await deployContract(ownerAcc, WETH9MockArtifact)) as WETH9Mock
    usdc = (await deployContract(ownerAcc, USDCMockArtifact)) as USDCMock
    dai = (await deployContract(ownerAcc, DAIMockArtifact)) as DAIMock

    curvePool = await deployContract(ownerAcc,CurvePoolMockArtifact) as unknown as CurvePoolMock
    await curvePool.set('1019568078072415210')
    usdcEthAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as unknown as ChainlinkAggregatorV3Mock
    daiEthAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as unknown as ChainlinkAggregatorV3Mock
    usdtEthAggregator = (await deployContract(ownerAcc, ChainlinkAggregatorV3MockArtifact)) as unknown as ChainlinkAggregatorV3Mock
    await usdcEthAggregator.set('230171858101077')
    await daiEthAggregator.set('230213930000000')
    await usdtEthAggregator.set('230334420255290')

    chainlinkMultiOracle = (await deployContract(ownerAcc, ChainlinkMultiOracleArtifact, [])) as ChainlinkMultiOracle
    await chainlinkMultiOracle.grantRole(
      id(chainlinkMultiOracle.interface, 'setSource(bytes6,address,bytes6,address,address)'),
      ownerAcc.address
    )

    //Set stETH/ETH chainlink oracle
    await chainlinkMultiOracle.setSource(DAI, dai.address, ETH, weth.address, daiEthAggregator.address)
    await chainlinkMultiOracle.setSource(USDC, usdc.address, ETH, weth.address, usdcEthAggregator.address)

    compositeMultiOracle = (await deployContract(ownerAcc, CompositeMultiOracleArtifact)) as CompositeMultiOracle
    compositeMultiOracle.grantRoles(
      [
        id(compositeMultiOracle.interface, 'setSource(bytes6,bytes6,address)'),
        id(compositeMultiOracle.interface, 'setPath(bytes6,bytes6,bytes6[])'),
      ],
      ownerAcc.address
    )
    

    DummyConvexCurveOracle = (await deployContract(ownerAcc, DummyConvexCurveOracleArtifact, [
        bytes6ToBytes32(CVX3CRV),
        bytes6ToBytes32(ETH),
        curvePool.address,
        daiEthAggregator.address,
        usdcEthAggregator.address,
        usdtEthAggregator.address,
    ])) as unknown as DummyConvexCurveOracle

    // Set up the CompositeMultiOracle to draw from the ChainlinkMultiOracle
    await compositeMultiOracle.setSource(CVX3CRV, ETH, DummyConvexCurveOracle.address)
    await compositeMultiOracle.setSource(DAI, ETH, chainlinkMultiOracle.address)
    await compositeMultiOracle.setSource(USDC, ETH, chainlinkMultiOracle.address)

    await compositeMultiOracle.setPath(DAI, CVX3CRV, [ETH])
    
    await compositeMultiOracle.setPath(USDC, CVX3CRV, [ETH])
  })

  it('Add integration', async () => {
    expect(await ladle.addIntegration(convex.address, true)).to.emit(ladle, 'IntegrationAdded')
    await wand.addAsset(CVX3CRV,convex.address)
    await witch.setIlk(CVX3CRV, 4 * 60 * 60, WAD.div(2), 1000000, 0, 18)
    await wand.makeIlk(USDC, CVX3CRV, DummyConvexCurveOracle.address, 1000000, 1000000, 1000000, 6)
  })

  it('routes calls through the Ladle', async () => {
    await convex.approve(ladle.address, parseEther('1'))

    const wrapCall = convex.interface.encodeFunctionData('deposit', [parseEther('1'), ladle.address])
    await ladle.route(convex.address, wrapCall)
    expect((await convex.balanceOf(ladle.address)).toString()).to.equals(parseEther('1').toString())
  })

  it('transfers wstEth through the Ladle', async () => {
    // await wstEth.connect(stEthWhaleAcc).approve(ladle.address, MAX256)
    // await ladle.connect(stEthWhaleAcc).transfer(wstEth.address, lidoWrapHandler.address, WAD)
  })

  it('transfers stEth through the Ladle', async () => {
    // await stEth.connect(stEthWhaleAcc).approve(ladle.address, MAX256)
    // await ladle.connect(stEthWhaleAcc).transfer(stEth.address, lidoWrapHandler.address, WAD)
  })
})
