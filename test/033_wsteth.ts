import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { ETH, DAI, USDC, WSTETH, STETH } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { LidoOracle } from '../typechain/LidoOracle'
import { LidoMock } from '../typechain/LidoMock'
import { STETHMock } from '../typechain/STETHMock'
import { ChainlinkAggregatorV3Mock } from '../typechain/ChainlinkAggregatorV3Mock'
import { YieldEnvironment } from './shared/fixtures'
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { CompositeMultiOracle } from '../typechain/CompositeMultiOracle'
import LidoOracleArtifact from '../artifacts/contracts/oracles/lido/LidoOracle.sol/LidoOracle.json'
import ChainlinkMultiOracleArtifact from '../artifacts/contracts/oracles/chainlink/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import CompositeMultiOracleArtifact from '../artifacts/contracts/oracles/composite/CompositeMultiOracle.sol/CompositeMultiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import CTokenMultiOracleArtifact from '../artifacts/contracts/oracles/compound/CTokenMultiOracle.sol/CTokenMultiOracle.json'
import CTokenMockArtifact from '../artifacts/contracts/mocks/oracles/compound/CTokenMock.sol/CTokenMock.json'
import USDCMockArtifact from '../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'
import STETHMockArtifact from '../artifacts/contracts/mocks/STETHMock.sol/STETHMock.json'
import WETH9MockArtifact from '../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import LidoMockArtifact from '../artifacts/contracts/mocks/oracles/lido/LidoMock.sol/LidoMock.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import { CTokenMultiOracle } from '../typechain/CTokenMultiOracle'
import { getLastVaultId } from '../src/helpers'
import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
import { Wand } from '../typechain/Wand'
import { Witch } from '../typechain/Witch'
import { WETH9Mock } from '../typechain/WETH9Mock'
import { parseEther } from 'ethers/lib/utils'
import { PoolMock } from '../typechain/PoolMock'
import { CTokenMock } from '../typechain/CTokenMock'
import { USDCMock } from '../typechain/USDCMock'
const { loadFixture } = waffle
const { deployContract } = waffle

var WSTETHADD = '0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0'

describe('WstETH', function () {
  this.timeout(0)
  let ownerAcc: SignerWithAddress
  let owner: string
  let otherAcc: SignerWithAddress
  let other: string
  let env: YieldEnvironment
  let cauldron: Cauldron
  let cauldronFromOther: Cauldron
  let wand: Wand
  let witch: Witch
  let fyToken: FYToken
  let usdc: USDCMock
  let cUSDC: CTokenMock
  let ilk: ERC20Mock
  let steth: STETHMock
  let chainlinkMultiOracle: ChainlinkMultiOracle
  let compositeMultiOracle: CompositeMultiOracle
  let cTokenMultiOracle: CTokenMultiOracle
  let lidoOracle: LidoOracle
  let lidoMock: LidoMock
  let stethEthAggregator: ChainlinkAggregatorV3Mock
  let stethUsdAggregator: ChainlinkAggregatorV3Mock
  let weth: WETH9Mock
  const baseId = ETH

  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  const otherIlkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const otherSeriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const cUSDCId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const oneUSDC = WAD.div(1000000000000)

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, otherIlkId], [otherSeriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()

    env = await YieldEnvironment.setup(ownerAcc, [baseId, USDC, otherIlkId], [otherSeriesId])
    wand = env.wand
    witch = env.witch
    cauldron = env.cauldron

    usdc = env.assets.get(USDC) as USDCMock
    steth = (await deployContract(ownerAcc, STETHMockArtifact)) as STETHMock
    weth = (env.assets.get(ETH) as unknown) as WETH9Mock
    cUSDC = (await deployContract(ownerAcc, CTokenMockArtifact, [usdc.address])) as CTokenMock

    ilk = (await deployContract(ownerAcc, ERC20MockArtifact, [
      'Wrapped liquid staked Ether 2.0',
      'wstETH',
    ])) as ERC20Mock
    await ilk.mint(ownerAcc.address, parseEther('1000000'))
    WSTETHADD = ilk.address

    // Setting up chainlink multi oracle
    chainlinkMultiOracle = (await deployContract(ownerAcc, ChainlinkMultiOracleArtifact, [])) as ChainlinkMultiOracle
    await chainlinkMultiOracle.grantRole(
      id(chainlinkMultiOracle.interface, 'setSource(bytes6,address,bytes6,address,address)'),
      owner
    )

    // Setting up Lido Oracle
    lidoMock = (await deployContract(ownerAcc, LidoMockArtifact)) as LidoMock
    lidoOracle = (await deployContract(ownerAcc, LidoOracleArtifact)) as LidoOracle
    await lidoOracle.grantRole(id(lidoOracle.interface, 'setSource(address)'), owner)
    await lidoOracle['setSource(address)'](lidoMock.address) //mockOracle
    await lidoMock.set('1008339308050006006')

    // Setting up stethEth Chainlink oracle
    stethEthAggregator = (await deployContract(
      ownerAcc,
      ChainlinkAggregatorV3MockArtifact
    )) as ChainlinkAggregatorV3Mock
    await stethEthAggregator.set('992966330000000000')
    await chainlinkMultiOracle.setSource(STETH, steth.address, ETH, weth.address, stethEthAggregator.address)

    // Setting up stethUsd Chainlink oracle
    stethUsdAggregator = (await deployContract(
      ownerAcc,
      ChainlinkAggregatorV3MockArtifact
    )) as ChainlinkAggregatorV3Mock
    await stethUsdAggregator.set('419348926478')
    await chainlinkMultiOracle.setSource(STETH, steth.address, USDC, usdc.address, stethUsdAggregator.address)

    // Setting up composite multi oracle
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
    await compositeMultiOracle.setSource(STETH, USDC, chainlinkMultiOracle.address)

    // Set path for wsteth-steth-eth
    await compositeMultiOracle.setPath(WSTETH, ETH, [STETH])

    // Set path for wsteth-steth-USDC
    await compositeMultiOracle.setPath(WSTETH, USDC, [STETH])

    cTokenMultiOracle = (await deployContract(ownerAcc, CTokenMultiOracleArtifact)) as CTokenMultiOracle
    await cTokenMultiOracle.grantRole(id(cTokenMultiOracle.interface, 'setSource(bytes6,bytes6,address)'), owner)
    await cTokenMultiOracle.setSource(cUSDCId, USDC, cUSDC.address)
    await cUSDC.set(WAD.mul(2).div(100)) // USDC has 6 + 10 decimals
  })

  it('WstETH could be added as an asset', async () => {
    await wand.addAsset(WSTETH, WSTETHADD)
  })

  it('Convert WstETH into an ilk', async () => {
    await witch.setIlk(WSTETH, 4 * 60 * 60, WAD.div(2), 1000000, 0, 18)
    await wand.makeIlk(baseId, WSTETH, lidoOracle.address, 1000000, 1000000, 1000000, 6)
  })

  it('Build & test ETH Borrowing', async () => {
    const { timestamp } = await ethers.provider.getBlock('latest')
    const THREEMONTHS = timestamp + 3 * 31 * 24 * 60 * 60

    // Add a series
    await wand.addSeries(seriesId, baseId, THREEMONTHS, [WSTETH], seriesId, seriesId)

    const fyToken = (await ethers.getContractAt(
      'FYToken',
      (await cauldron.series(seriesId)).fyToken,
      ownerAcc
    )) as FYToken

    const pool = (await ethers.getContractAt('PoolMock', await env.ladle.pools(seriesId), ownerAcc)) as PoolMock
    await pool.mint(ownerAcc.address, true, 0)
    await fyToken.grantRole(id(fyToken.interface, 'mint(address,uint256)'), ownerAcc.address) // Only test environment
    await fyToken.mint(pool.address, WAD.mul(2100000))
    await pool.sync()

    // Build a vault
    await env.ladle.build(seriesId, WSTETH)
    var vaultId = await getLastVaultId(cauldron)

    var join = await env.ladle.joins(WSTETH)

    // Transfer the amount to join before pouring
    await ilk.transfer(join, parseEther('1'))

    // Pour the amount into the pool & borrow
    expect(await env.ladle.pour(vaultId, ownerAcc.address, parseEther('0.5'), parseEther('0.000001'))).to.emit(
      cauldron,
      'VaultPoured'
    )

    expect(await fyToken['balanceOf(address)'](ownerAcc.address)).to.eq(parseEther('0.000001'))
  })

  it('Build & test USDC borrowing', async () => {
    await wand.makeBase(USDC, compositeMultiOracle.address)
    await cauldron.setLendingOracle(USDC, compositeMultiOracle.address)
    // await witch.setIlk(WSTETH, 4 * 60 * 60, WAD.div(2), 1000000, 0, 18)
    await wand.makeIlk(USDC, WSTETH, compositeMultiOracle.address, 1000000, 1000000, 1000000, 6)

    const { timestamp } = await ethers.provider.getBlock('latest')
    const THREEMONTHS = timestamp + 3 * 31 * 24 * 60 * 60
    var seriesId2 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
    // Add a series
    await wand.addSeries(seriesId2, USDC, THREEMONTHS, [WSTETH], seriesId2, seriesId2)

    const fyToken = (await ethers.getContractAt(
      'FYToken',
      (await cauldron.series(seriesId2)).fyToken,
      ownerAcc
    )) as FYToken

    const pool = (await ethers.getContractAt('PoolMock', await env.ladle.pools(seriesId2), ownerAcc)) as PoolMock
    await pool.mint(ownerAcc.address, true, 0)
    await fyToken.grantRole(id(fyToken.interface, 'mint(address,uint256)'), ownerAcc.address) // Only test environment
    await fyToken.mint(pool.address, WAD.mul(2100000))
    await pool.sync()

    // Build a vault
    await env.ladle.build(seriesId2, WSTETH)
    var vaultId = await getLastVaultId(cauldron)

    var join = await env.ladle.joins(WSTETH)

    // Transfer the amount to join before pouring
    await ilk.transfer(join, parseEther('1'))

    expect(await env.ladle.pour(vaultId, ownerAcc.address, parseEther('0.5'), parseEther('0.000001'))).to.emit(
      cauldron,
      'VaultPoured'
    )
  })
})
