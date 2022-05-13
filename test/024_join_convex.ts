import { ethers, network, waffle } from 'hardhat'
import { YieldEnvironment } from './shared/fixtures'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { expect } from 'chai'
import { ETH, DAI, USDC, CVX3CRV } from '../src/constants'
import {
  ERC20Mock,
  ConvexModule,
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
  TokenProxy,
  ConvexJoin,
} from '../typechain'

import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import Cvx3CrvOracleArtifact from '../artifacts/contracts/oracles/convex/Cvx3CrvOracle.sol/Cvx3CrvOracle.json'
import CurvePoolMockArtifact from '../artifacts/contracts/mocks/oracles/convex/CurvePoolMock.sol/CurvePoolMock.json'
import CompositeMultiOracleArtifact from '../artifacts/contracts/oracles/composite/CompositeMultiOracle.sol/CompositeMultiOracle.json'
import ConvexLadleModuleArtifact from '../artifacts/contracts/other/convex/ConvexModule.sol/ConvexModule.json'
import ConvexPoolMockArtifact from '../artifacts/contracts/mocks/ConvexPoolMock.sol/ConvexPoolMock.json'
import ConvexJoinArtifact from '../artifacts/contracts/other/convex/ConvexJoin.sol/ConvexJoin.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import TokenProxyArtifact from '../artifacts/contracts/mocks/TokenProxy.sol/TokenProxy.json'
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
 * @dev This script tests the ConvexJoin and ConvexLadleModule integration with the Ladle
 */
describe('Convex Join', async function () {
  this.timeout(0)

  let ladle: LadleWrapper
  let wand: Wand
  let witch: Witch
  let ownerAcc: SignerWithAddress
  let dummyAcc: SignerWithAddress
  let cauldron: Cauldron
  let convex: ERC20Mock
  let crv: ERC20Mock
  let cvx3CRV: ERC20Mock
  let convexPool: ConvexPoolMock
  let curveProxy: TokenProxy
  let cvxProxy: TokenProxy
  let convexJoin: ConvexJoin

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
    dummyAcc = signers[1]
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
    curveProxy = (await deployContract(ownerAcc, TokenProxyArtifact, [crv.address])) as TokenProxy
    cvxProxy = (await deployContract(ownerAcc, TokenProxyArtifact, [convex.address])) as TokenProxy
    convexJoin = (await deployContract(ownerAcc, ConvexJoinArtifact, [
      crv.address,
      cvx3CRV.address,
      convexPool.address,
      0,
      cauldron.address,
      'stk',
      'wCVX3CRV',
      18,
    ])) as unknown as ConvexJoin
    await convexJoin.grantRoles(
      [
        id(convexJoin.interface, 'join(address,uint128)'),
        id(convexJoin.interface, 'exit(address,uint128)'),
        id(convexJoin.interface, 'addVault(bytes12)'),
        id(convexJoin.interface, 'removeVault(bytes12,address)'),
      ],
      ladle.address
    )
    await cauldron.addAsset(CVX3CRV, cvx3CRV.address)
    await ladle.addJoin(CVX3CRV, convexJoin.address)

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

    // Setting the mainnet crv to mock CRV
    const crv_proxy_code = await ethers.provider.getCode(curveProxy.address)
    expect(await network.provider.send('hardhat_setCode', [await convexJoin.crv(), crv_proxy_code])).to.be.true
    // Setting the mainnet cvx to mock CVX
    const cvx_proxy_code = await ethers.provider.getCode(cvxProxy.address)
    expect(await network.provider.send('hardhat_setCode', [await convexJoin.cvx(), cvx_proxy_code])).to.be.true

    // Add Module
    await ladle.ladle.addModule(convexLadleModule.address, true)

    fyToken = env.series.get(seriesId) as FYToken

    // Add Join to ladle
    await witch.setIlk(CVX3CRV, 4 * 60 * 60, WAD.div(2), 1000000, 0, 18)

    await ladle.ladle.addToken(cvx3CRV.address, true)

    await cvx3CRV.mint(ownerAcc.address, ethers.utils.parseEther('10'))
    await crv.mint(convexPool.address, ethers.utils.parseEther('10'))
    await convex.mint(convexPool.address, ethers.utils.parseEther('10'))

    //Minting tokens to the proxy
    await crv.mint(await convexJoin.crv(), ethers.utils.parseEther('10'))
    await convex.mint(await convexJoin.cvx(), ethers.utils.parseEther('10'))
  })

  it('Borrow USDC with CVX3CRV collateral', async () => {
    await cauldron.setSpotOracle(USDC, CVX3CRV, compositeMultiOracle.address, 1000000)
    await cauldron.setDebtLimits(USDC, CVX3CRV, 1000000, 1, 6)
    await cauldron.addIlks(seriesId, [CVX3CRV])
    var join = await ladle.joins(CVX3CRV)
    // Batch action to build a vault & add it to the wrapper
    const addVaultCall = convexLadleModule.interface.encodeFunctionData('addVault', [
      convexJoin.address,
      '0x000000000000000000000000',
    ])
    await ladle.batch([
      ladle.buildAction(seriesId, CVX3CRV),
      ladle.moduleCallAction(convexLadleModule.address, addVaultCall),
    ])
    var cvx3CrvBefore = (await cvx3CRV.balanceOf(ownerAcc.address)).toString()

    var vaultId = await getLastVaultId(cauldron)

    expect(await convexJoin.vaults(ownerAcc.address, [0])).to.eq(vaultId)

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

    await ladle.batch([
      ladle.transferAction(cvx3CRV.address, join, posted),
      ladle.pourAction(vaultId, ownerAcc.address, posted, borrowed),
    ])

    expect(await fyToken.balanceOf(ownerAcc.address)).to.eq(borrowed)

    if ((await cauldron.balances(vaultId)).art.toString() !== borrowed.toString()) throw 'art mismatch'
    if ((await cauldron.balances(vaultId)).ink.toString() !== posted.toString()) throw 'ink mismatch'

    console.log('Borrowed Successfully')
    var crvBefore = await crv.balanceOf(ownerAcc.address)
    var cvxBefore = await convex.balanceOf(ownerAcc.address)
    // Claim CVX & CRV reward
    console.log('Claiming Reward')
    await convexJoin.getReward(ownerAcc.address)
    var crvAfter = await crv.balanceOf(ownerAcc.address)
    var cvxAfter = await convex.balanceOf(ownerAcc.address)
    console.log('User Total Crv ' + crvAfter.toString())
    console.log('Earned Crv ' + crvAfter.sub(crvBefore).toString())
    console.log('User Total cvx ' + cvxAfter.toString())
    console.log('Earned cvx ' + cvxAfter.sub(cvxBefore).toString())
    if (crvBefore.gt(crvAfter)) throw 'Reward claim failed'
    if (cvxBefore.gt(cvxAfter)) throw 'Reward claim failed'

    // Repay fyDai and withdraw cvx3Crv
    await fyToken.transfer(fyToken.address, borrowed)

    await ladle.pour(vaultId, ownerAcc.address, posted.mul(-1), borrowed.mul(-1))

    console.log(`repaid and withdrawn`)
    const cvx3CrvAfter = (await cvx3CRV.balanceOf(ownerAcc.address)).toString()
    console.log(`${cvx3CrvAfter} cvx3Crv after`)
    if (cvx3CrvAfter !== cvx3CrvBefore) throw 'cvx3Crv balance mismatch'
    console.log('Claiming leftover rewards')
    // Claim leftover rewards
    crvBefore = await crv.balanceOf(ownerAcc.address)
    cvxBefore = await convex.balanceOf(ownerAcc.address)
    await convexJoin.getReward(ownerAcc.address)
    crvAfter = await crv.balanceOf(ownerAcc.address)
    cvxAfter = await convex.balanceOf(ownerAcc.address)
    console.log('User Earned Crv ' + crvAfter.sub(crvBefore).toString())
    console.log('Total User Crv ' + crvAfter.toString())
    console.log('User Earned cvx ' + cvxAfter.sub(cvxBefore).toString())
    console.log('Total User cvx ' + cvxAfter.toString())
    if (crvBefore.gt(crvAfter)) throw 'Reward claim failed'
    if (cvxBefore.gt(cvxAfter)) throw 'Reward claim failed'
  })

  it('Borrow DAI with CVX3CRV collateral', async () => {
    await cauldron.setSpotOracle(DAI, CVX3CRV, compositeMultiOracle.address, 1000000)
    await cauldron.setDebtLimits(DAI, CVX3CRV, 1000000, 1, 18)
    await cauldron.addIlks(seriesId, [CVX3CRV])
    var join = await ladle.joins(CVX3CRV)

    // Batch action to build a vault & add it to the wrapper
    const addVaultCall = convexLadleModule.interface.encodeFunctionData('addVault', [
      convexJoin.address,
      '0x000000000000000000000000',
    ])
    await ladle.batch([
      ladle.buildAction(seriesId, CVX3CRV),
      ladle.moduleCallAction(convexLadleModule.address, addVaultCall),
    ])
    var vaultId = await getLastVaultId(cauldron)
    var cvx3CrvBefore = (await cvx3CRV.balanceOf(ownerAcc.address)).toString()
    expect(await convexJoin.vaults(ownerAcc.address, [1])).to.eq(vaultId)

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

    var beforeJoinBalance = await convexJoin.balanceOf(join)
    var beforeFyTokenBalance = await fyToken.balanceOf(ownerAcc.address)
    await ladle.batch([
      ladle.transferAction(cvx3CRV.address, join, posted),
      ladle.pourAction(vaultId, ownerAcc.address, posted, borrowed),
    ])

    expect(await fyToken.balanceOf(ownerAcc.address)).to.eq(borrowed.add(beforeFyTokenBalance))

    if ((await cauldron.balances(vaultId)).art.toString() !== borrowed.toString()) throw 'art mismatch'
    if ((await cauldron.balances(vaultId)).ink.toString() !== posted.toString()) throw 'ink mismatch'

    console.log('Borrowed Successfully')
    var crvBefore = await crv.balanceOf(ownerAcc.address)
    var cvxBefore = await convex.balanceOf(ownerAcc.address)
    // Claim CVX & CRV reward
    console.log('Claiming Reward')
    await convexJoin.getReward(ownerAcc.address)
    var crvAfter = await crv.balanceOf(ownerAcc.address)
    var cvxAfter = await convex.balanceOf(ownerAcc.address)
    console.log('User Total Crv ' + crvAfter.toString())
    console.log('User Earned Crv ' + crvAfter.sub(crvBefore).toString())
    console.log('User Total cvx ' + cvxAfter.toString())
    console.log('Earned cvx ' + cvxAfter.sub(cvxBefore).toString())
    if (crvBefore.gt(crvAfter)) throw 'Reward claim failed'
    if (cvxBefore.gt(cvxAfter)) throw 'Reward claim failed'

    // Repay fyDai and withdraw cvx3Crv
    await fyToken.transfer(fyToken.address, borrowed)

    await ladle.pour(vaultId, ownerAcc.address, posted.mul(-1), borrowed.mul(-1)), console.log(`repaid and withdrawn`)
    const cvx3CrvAfter = (await cvx3CRV.balanceOf(ownerAcc.address)).toString()
    console.log(`${cvx3CrvAfter} cvx3Crv after`)
    if (cvx3CrvAfter !== cvx3CrvBefore) throw 'cvx3Crv balance mismatch'
    console.log('Claiming leftover rewards')
    // Claim leftover rewards
    crvBefore = await crv.balanceOf(ownerAcc.address)
    cvxBefore = await convex.balanceOf(ownerAcc.address)
    await convexJoin.getReward(ownerAcc.address)
    crvAfter = await crv.balanceOf(ownerAcc.address)
    cvxAfter = await convex.balanceOf(ownerAcc.address)
    console.log('User Earned Crv ' + crvAfter.sub(crvBefore).toString())
    console.log('Total User Crv ' + crvAfter.toString())
    console.log('User Earned cvx ' + cvxAfter.sub(cvxBefore).toString())
    console.log('Total User cvx ' + cvxAfter.toString())
    if (crvBefore.gt(crvAfter)) throw 'Reward claim failed'
    if (cvxBefore.gt(cvxAfter)) throw 'Reward claim failed'
  })

  it('Adding a vault for a different collateral fails', async () => {
    const addVaultCall = convexLadleModule.interface.encodeFunctionData('addVault', [
      convexJoin.address,
      '0x000000000000000000000000',
    ])
    await expect(
      ladle.batch([ladle.buildAction(seriesId, USDC), ladle.moduleCallAction(convexLadleModule.address, addVaultCall)])
    ).to.be.revertedWith('Vault is for different ilk')
  })

  it('Remove vault in different call', async () => {
    // Batch action to build a vault & add it to the wrapper
    const addVaultCall = convexLadleModule.interface.encodeFunctionData('addVault', [
      convexJoin.address,
      '0x000000000000000000000000',
    ])

    await ladle.batch([
      ladle.buildAction(seriesId, CVX3CRV),
      ladle.moduleCallAction(convexLadleModule.address, addVaultCall),
    ])

    await cauldron.give(await getLastVaultId(cauldron), dummyAcc.address)

    const removeVaultCall = convexLadleModule.interface.encodeFunctionData('removeVault', [
      convexJoin.address,
      await getLastVaultId(cauldron),
      ownerAcc.address,
    ])

    expect(await convexJoin.vaults(ownerAcc.address, [2])).to.be.eq(await getLastVaultId(cauldron))
    await ladle.batch([ladle.moduleCallAction(convexLadleModule.address, removeVaultCall)])
    await expect(convexJoin.vaults(ownerAcc.address, [2])).to.be.revertedWith('')
  })

  it('Vault belonging to a user cant be removed', async () => {
    // Batch action to build a vault & add it to the wrapper
    const addVaultCall = convexLadleModule.interface.encodeFunctionData('addVault', [
      convexJoin.address,
      '0x000000000000000000000000',
    ])

    await ladle.batch([
      ladle.buildAction(seriesId, CVX3CRV),
      ladle.moduleCallAction(convexLadleModule.address, addVaultCall),
    ])

    const removeVaultCall = convexLadleModule.interface.encodeFunctionData('removeVault', [
      convexJoin.address,
      await getLastVaultId(cauldron),
      ownerAcc.address,
    ])

    expect(await convexJoin.vaults(ownerAcc.address, [2])).to.be.eq(await getLastVaultId(cauldron))
    await expect(ladle.batch([ladle.moduleCallAction(convexLadleModule.address, removeVaultCall)])).to.be.revertedWith(
      'vault belongs to account'
    )
  })
})
