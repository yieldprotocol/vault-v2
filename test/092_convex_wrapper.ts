import { ethers, waffle } from 'hardhat'
import { YieldEnvironment } from './shared/fixtures'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { expect } from 'chai'
import { ETH, DAI, USDC, CVX3CRV } from '../src/constants'
import {
  ERC20Mock,
  ConvexModule,
  ConvexYieldWrapperMock,
  ConvexPoolMock,
  ChainlinkMultiOracle,
  Wand,
  Witch,
  CompositeMultiOracle,
  CurvePoolMock,
  Cvx3CrvOracle,
  ChainlinkAggregatorV3Mock,
  WETH9Mock,
  DAIMock,
  USDCMock,
  Cauldron,
  FYToken,
} from '../typechain'

import ConvexYieldWrapperMockArtifact from '../artifacts/contracts/mocks/ConvexYieldWrapperMock.sol/ConvexYieldWrapperMock.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import Cvx3CrvOracleArtifact from '../artifacts/contracts/oracles/convex/Cvx3CrvOracle.sol/Cvx3CrvOracle.json'
import CurvePoolMockArtifact from '../artifacts/contracts/mocks/oracles/convex/CurvePoolMock.sol/CurvePoolMock.json'
import CompositeMultiOracleArtifact from '../artifacts/contracts/oracles/composite/CompositeMultiOracle.sol/CompositeMultiOracle.json'
import ConvexLadleModuleArtifact from '../artifacts/contracts/utils/convex/ConvexModule.sol/ConvexModule.json'
import ConvexPoolMockArtifact from '../artifacts/contracts/mocks/ConvexPoolMock.sol/ConvexPoolMock.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { parseEther } from '@ethersproject/units'
import { getLastVaultId } from '../src/helpers'
import { BigNumber } from '@ethersproject/bignumber'
import { LadleWrapper } from '../src/ladleWrapper'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}
function bytesToString(bytes: string): string {
  return ethers.utils.parseBytes32String(bytes + '0'.repeat(66 - bytes.length))
}
function stringToBytes32(x: string): string {
  return ethers.utils.formatBytes32String(x)
}
function bytesToBytes32(bytes: string): string {
  return stringToBytes32(bytesToString(bytes))
}

/**
 * @dev This script tests the convexwrapper and ConvexLadleModule integration with the Ladle
 */
describe('Convex Wrapper', async function () {
  let ladle: LadleWrapper
  let wand: Wand
  let witch: Witch
  let ownerAcc: SignerWithAddress
  let cauldron: Cauldron
  let convex: ERC20Mock
  let crv: ERC20Mock
  let cvx3CRV: ERC20Mock
  let convexWrapper: ConvexYieldWrapperMock
  let convexPool: ConvexPoolMock

  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId2 = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  let cvx3CrvOracle: Cvx3CrvOracle
  let daiEthAggregator: ChainlinkAggregatorV3Mock
  let usdcEthAggregator: ChainlinkAggregatorV3Mock
  let usdtEthAggregator: ChainlinkAggregatorV3Mock
  let curvePool: CurvePoolMock

  let weth: WETH9Mock
  let dai: DAIMock
  let usdc: USDCMock
  let fyToken: FYToken

  let chainlinkMultiOracle: ChainlinkMultiOracle
  let compositeMultiOracle: CompositeMultiOracle

  let convexLadleModule: ConvexModule

  let env: YieldEnvironment

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [USDC, DAI, ETH], [seriesId, seriesId2])
  }
  before(async () => {
    this.timeout(0)

    const signers = await ethers.getSigners()
    ownerAcc = signers[0]

    env = await fixture()
    ladle = env.ladle
    wand = env.wand
    witch = env.witch
    cauldron = env.cauldron

    await ladle.grantRoles(
      [id(ladle.ladle.interface, 'addToken(address,bool)'), id(ladle.ladle.interface, 'addIntegration(address,bool)')],
      ownerAcc.address
    )

    usdc = env.assets.get(USDC) as USDCMock //(await deployContract(ownerAcc, USDCMockArtifact)) as USDCMock
    weth = env.assets.get(ETH) as unknown as WETH9Mock
    dai = env.assets.get(DAI) as unknown as DAIMock
    convex = (await deployContract(ownerAcc, ERC20MockArtifact, ['Convex Token', 'CVX'])) as ERC20Mock
    cvx3CRV = (await deployContract(ownerAcc, ERC20MockArtifact, [
      'Curve.fi DAI/USDC/USDT Convex Deposit  Mock',
      'Cvx3Crv Mock',
    ])) as ERC20Mock
    crv = (await deployContract(ownerAcc, ERC20MockArtifact, ['CurveDAO Token Mock', 'CRV'])) as ERC20Mock
    await convex.mint(ownerAcc.address, parseEther('1000000'))

    curvePool = (await deployContract(ownerAcc, CurvePoolMockArtifact)) as unknown as CurvePoolMock
    convexPool = (await deployContract(ownerAcc, ConvexPoolMockArtifact, [
      crv.address,
      cvx3CRV.address,
      convex.address,
    ])) as unknown as ConvexPoolMock

    usdcEthAggregator = (await deployContract(
      ownerAcc,
      ChainlinkAggregatorV3MockArtifact
    )) as unknown as ChainlinkAggregatorV3Mock
    daiEthAggregator = (await deployContract(
      ownerAcc,
      ChainlinkAggregatorV3MockArtifact
    )) as unknown as ChainlinkAggregatorV3Mock
    usdtEthAggregator = (await deployContract(
      ownerAcc,
      ChainlinkAggregatorV3MockArtifact
    )) as unknown as ChainlinkAggregatorV3Mock
    cvx3CrvOracle = (await deployContract(ownerAcc, Cvx3CrvOracleArtifact)) as unknown as Cvx3CrvOracle
    convexLadleModule = (await deployContract(ownerAcc, ConvexLadleModuleArtifact, [
      cauldron.address,
      weth.address,
    ])) as ConvexModule
    compositeMultiOracle = (await deployContract(ownerAcc, CompositeMultiOracleArtifact)) as CompositeMultiOracle
    chainlinkMultiOracle = env.oracles.get(ETH) as unknown as ChainlinkMultiOracle

    convexWrapper = (await deployContract(ownerAcc, ConvexYieldWrapperMockArtifact, [
      cvx3CRV.address,
      convexPool.address,
      0,
      '0x0000000000000000000000000000000000000000',
      cauldron.address,
      crv.address,
      convex.address,
    ])) as unknown as ConvexYieldWrapperMock

    await usdcEthAggregator.set('230171858101077')
    await daiEthAggregator.set('230213930000000')
    await usdtEthAggregator.set('230334420255290')
    await curvePool.set('1019568078072415210')

    await chainlinkMultiOracle.grantRole(
      id(chainlinkMultiOracle.interface, 'setSource(bytes6,address,bytes6,address,address)'),
      ownerAcc.address
    )
    await compositeMultiOracle.grantRoles(
      [
        id(compositeMultiOracle.interface, 'setSource(bytes6,bytes6,address)'),
        id(compositeMultiOracle.interface, 'setPath(bytes6,bytes6,bytes6[])'),
      ],
      ownerAcc.address
    )
    await cauldron.grantRoles([id(cauldron.interface, 'addIlks(bytes6,bytes6[])')], ownerAcc.address)
    await ladle.grantRoles([id(ladle.ladle.interface, 'addIntegration(address,bool)')], ownerAcc.address)
    await ladle.grantRoles([id(ladle.ladle.interface, 'addModule(address,bool)')], ownerAcc.address)
    await cvx3CrvOracle.grantRole(
      id(cvx3CrvOracle.interface, 'setSource(bytes32,bytes32,address,address,address,address)'),
      ownerAcc.address
    )

    await cvx3CrvOracle['setSource(bytes32,bytes32,address,address,address,address)'](
      bytes6ToBytes32(CVX3CRV),
      bytes6ToBytes32(ETH),
      curvePool.address,
      daiEthAggregator.address,
      usdcEthAggregator.address,
      usdtEthAggregator.address
    )

    await chainlinkMultiOracle.setSource(DAI, dai.address, ETH, weth.address, daiEthAggregator.address)
    await chainlinkMultiOracle.setSource(USDC, usdc.address, ETH, weth.address, usdcEthAggregator.address)

    // Set up the CompositeMultiOracle to draw from the ChainlinkMultiOracle
    await compositeMultiOracle.setSource(CVX3CRV, ETH, cvx3CrvOracle.address)
    await compositeMultiOracle.setSource(DAI, ETH, chainlinkMultiOracle.address)
    await compositeMultiOracle.setSource(USDC, ETH, chainlinkMultiOracle.address)
    await compositeMultiOracle.setPath(DAI, CVX3CRV, [ETH])
    await compositeMultiOracle.setPath(USDC, CVX3CRV, [ETH])

    // Add integrations
    await ladle.ladle.addIntegration(convexWrapper.address, true)

    // Add Module
    await ladle.ladle.addModule(convexLadleModule.address, true)

    fyToken = env.series.get(seriesId) as FYToken

    await wand.addAsset(CVX3CRV, convexWrapper.address)
    await witch.setIlk(CVX3CRV, 4 * 60 * 60, WAD.div(2), 1000000, 0, 18)

    await ladle.ladle.addToken(cvx3CRV.address, true)

    await cvx3CRV.mint(ownerAcc.address, ethers.utils.parseEther('100000'))
    await crv.mint(convexPool.address, ethers.utils.parseEther('100000'))
    await convex.mint(convexPool.address, ethers.utils.parseEther('100000'))
  })

  it('Borrow USDC with CVX3CRV collateral', async () => {
    await wand.makeIlk(USDC, CVX3CRV, compositeMultiOracle.address, 1000000, 1000000, 1, 6)
    await cauldron.addIlks(seriesId, [CVX3CRV])
    var join = await ladle.joins(CVX3CRV)
    await convexWrapper.point(join)
    // Batch action to build a vault & add it to the wrapper
    const addVaultCall = convexLadleModule.interface.encodeFunctionData('addVault', [
      convexWrapper.address,
      '0x000000000000000000000000',
    ])
    await ladle.batch([
      ladle.buildAction(seriesId, CVX3CRV),
      ladle.moduleCallAction(convexLadleModule.address, addVaultCall),
    ])

    var vaultId = await getLastVaultId(cauldron)

    expect(await convexWrapper.vaults(ownerAcc.address, [0])).to.eq(vaultId)

    const dust = (await cauldron.debt(USDC, CVX3CRV)).min
    const ratio = (await cauldron.spotOracles(USDC, CVX3CRV)).ratio
    const borrowed = BigNumber.from(10)
      .pow(await fyToken.decimals())
      .mul(dust)
    const posted = (await compositeMultiOracle.peek(bytesToBytes32(USDC), bytesToBytes32(CVX3CRV), borrowed))[0]
      .mul(ratio)
      .div(1000000)
      .mul(101)
      .div(100)

    // Transfer the amount to join before pouring
    await cvx3CRV.approve(ladle.address, posted)
    const wrapCall = convexWrapper.interface.encodeFunctionData('wrap', [join, ownerAcc.address])

    await ladle.batch([
      ladle.transferAction(cvx3CRV.address, convexWrapper.address, posted),
      ladle.routeAction(convexWrapper.address, wrapCall),
      ladle.pourAction(vaultId, ownerAcc.address, posted, borrowed),
    ])

    expect(await convexWrapper.balanceOf(join)).to.eq(posted)
    expect(await fyToken.balanceOf(ownerAcc.address)).to.eq(borrowed)
  })

  it('Borrow DAI with CVX3CRV collateral', async () => {
    await wand.makeIlk(DAI, CVX3CRV, compositeMultiOracle.address, 1000000, 1000000, 1, 18)
    await cauldron.addIlks(seriesId, [CVX3CRV])
    var join = await ladle.joins(CVX3CRV)

    // Batch action to build a vault & add it to the wrapper
    const addVaultCall = convexLadleModule.interface.encodeFunctionData('addVault', [
      convexWrapper.address,
      '0x000000000000000000000000',
    ])
    await ladle.batch([
      ladle.buildAction(seriesId, CVX3CRV),
      ladle.moduleCallAction(convexLadleModule.address, addVaultCall),
    ])
    var vaultId = await getLastVaultId(cauldron)

    expect(await convexWrapper.vaults(ownerAcc.address, [1])).to.eq(vaultId)

    const dust = (await cauldron.debt(DAI, CVX3CRV)).min
    const ratio = (await cauldron.spotOracles(DAI, CVX3CRV)).ratio
    const borrowed = BigNumber.from(10)
      .pow(await fyToken.decimals())
      .mul(dust)
    const posted = (
      await compositeMultiOracle.peek(bytesToBytes32(DAI), bytesToBytes32(CVX3CRV), borrowed.mul(1000000000000))
    )[0]
      .mul(ratio)
      .div(1000000)
      .mul(101)
      .div(100)
    // Transfer the amount to join before pouring
    await cvx3CRV.approve(ladle.address, posted)
    const wrapCall = convexWrapper.interface.encodeFunctionData('wrap', [join, ownerAcc.address])
    var beforeJoinBalance = await convexWrapper.balanceOf(join)
    var beforeFyTokenBalance = await fyToken.balanceOf(ownerAcc.address)
    await ladle.batch([
      ladle.transferAction(cvx3CRV.address, convexWrapper.address, posted),
      ladle.routeAction(convexWrapper.address, wrapCall),
      ladle.pourAction(vaultId, ownerAcc.address, posted, borrowed),
    ])

    expect(await convexWrapper.balanceOf(join)).to.eq(posted.add(beforeJoinBalance))
    expect(await fyToken.balanceOf(ownerAcc.address)).to.eq(borrowed.add(beforeFyTokenBalance))
  })

  it('Adding a vault for a different collateral fails', async () => {
    const addVaultCall = convexLadleModule.interface.encodeFunctionData('addVault', [
      convexWrapper.address,
      '0x000000000000000000000000',
    ])
    await expect(
      ladle.batch([ladle.buildAction(seriesId, USDC), ladle.moduleCallAction(convexLadleModule.address, addVaultCall)])
    ).to.be.revertedWith('Vault is for different ilk')
  })

  it('Remove vault in the same call', async () => {
    await wand.makeIlk(DAI, CVX3CRV, compositeMultiOracle.address, 1000000, 1000000, 1, 18)
    await cauldron.addIlks(seriesId, [CVX3CRV])

    // Batch action to build a vault & add it to the wrapper
    const addVaultCall = convexLadleModule.interface.encodeFunctionData('addVault', [
      convexWrapper.address,
      '0x000000000000000000000000',
    ])

    const removeVaultCall = convexLadleModule.interface.encodeFunctionData('removeVault', [
      convexWrapper.address,
      '0x000000000000000000000000',
      ownerAcc.address,
    ])

    await ladle.batch([
      ladle.buildAction(seriesId, CVX3CRV),
      ladle.moduleCallAction(convexLadleModule.address, addVaultCall),
      ladle.moduleCallAction(convexLadleModule.address, removeVaultCall),
    ])

    await expect(convexWrapper.vaults(ownerAcc.address, [2])).to.be.revertedWith('')
  })

  it('Remove vault in different call', async () => {
    await wand.makeIlk(DAI, CVX3CRV, compositeMultiOracle.address, 1000000, 1000000, 1, 18)
    await cauldron.addIlks(seriesId, [CVX3CRV])

    // Batch action to build a vault & add it to the wrapper
    const addVaultCall = convexLadleModule.interface.encodeFunctionData('addVault', [
      convexWrapper.address,
      '0x000000000000000000000000',
    ])

    await ladle.batch([
      ladle.buildAction(seriesId, CVX3CRV),
      ladle.moduleCallAction(convexLadleModule.address, addVaultCall),
    ])

    const removeVaultCall = convexLadleModule.interface.encodeFunctionData('removeVault', [
      convexWrapper.address,
      await getLastVaultId(cauldron),
      ownerAcc.address,
    ])

    expect(await convexWrapper.vaults(ownerAcc.address, [2])).to.be.eq(await getLastVaultId(cauldron))
    await ladle.batch([ladle.moduleCallAction(convexLadleModule.address, removeVaultCall)])
    await expect(convexWrapper.vaults(ownerAcc.address, [2])).to.be.revertedWith('')
  })
})
