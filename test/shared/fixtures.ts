import { id, constants } from '@yield-protocol/utils-v2'

import { sendStatic } from './helpers'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

const { WAD, THREE_MONTHS, ETH, DAI, USDC } = constants
import { CHI, RATE } from '../../src/constants'

import CauldronArtifact from '../../artifacts/contracts/Cauldron.sol/Cauldron.json'
import LadleArtifact from '../../artifacts/contracts/Ladle.sol/Ladle.json'
import WandArtifact from '../../artifacts/contracts/Wand.sol/Wand.json'
import WitchArtifact from '../../artifacts/contracts/Witch.sol/Witch.json'
import JoinFactoryArtifact from '../../artifacts/contracts/JoinFactory.sol/JoinFactory.json'
import PoolFactoryMockArtifact from '../../artifacts/contracts/mocks/PoolFactoryMock.sol/PoolFactoryMock.json'

import ChainlinkMultiOracleArtifact from '../../artifacts/contracts/oracles/chainlink/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import CompoundMultiOracleArtifact from '../../artifacts/contracts/oracles/compound/CompoundMultiOracle.sol/CompoundMultiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../../artifacts/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import CTokenRateMockArtifact from '../../artifacts/contracts/mocks/oracles/compound/CTokenRateMock.sol/CTokenRateMock.json'
import CTokenChiMockArtifact from '../../artifacts/contracts/mocks/oracles/compound/CTokenChiMock.sol/CTokenChiMock.json'

import ERC20MockArtifact from '../../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import WETH9MockArtifact from '../../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import DAIMockArtifact from '../../artifacts/contracts/mocks/DAIMock.sol/DAIMock.json'
import USDCMockArtifact from '../../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'

import { Cauldron } from '../../typechain/Cauldron'
import { Join } from '../../typechain/Join'
import { FYToken } from '../../typechain/FYToken'
import { Ladle } from '../../typechain/Ladle'
import { Witch } from '../../typechain/Witch'
import { JoinFactory } from '../../typechain/JoinFactory'
import { FYTokenFactory } from '../../typechain/FYTokenFactory'
import { Wand } from '../../typechain/Wand'
import { PoolMock } from '../../typechain/PoolMock'
import { PoolFactoryMock } from '../../typechain/PoolFactoryMock'
import { OracleMock } from '../../typechain/OracleMock'
import { ISourceMock } from '../../typechain/ISourceMock'
import { ChainlinkMultiOracle } from '../../typechain/ChainlinkMultiOracle'
import { CompoundMultiOracle } from '../../typechain/CompoundMultiOracle'
import { SafeERC20Namer } from '../../typechain/SafeERC20Namer'

import { ERC20Mock } from '../../typechain/ERC20Mock'
import { WETH9Mock } from '../../typechain/WETH9Mock'
import { DAIMock } from '../../typechain/DAIMock'
import { USDCMock } from '../../typechain/USDCMock'

import { LadleWrapper } from '../../src/ladleWrapper'
import { getLastVaultId } from '../../src/helpers'

import { ethers, waffle } from 'hardhat'
const { deployContract } = waffle

export class YieldEnvironment {
  owner: SignerWithAddress
  cauldron: Cauldron
  ladle: LadleWrapper
  witch: Witch
  joinFactory: JoinFactory
  poolFactory: PoolFactoryMock
  wand: Wand
  assets: Map<string, ERC20Mock>
  oracles: Map<string, OracleMock>
  series: Map<string, FYToken>
  pools: Map<string, PoolMock>
  joins: Map<string, Join>
  vaults: Map<string, Map<string, string>>

  constructor(
    owner: SignerWithAddress,
    cauldron: Cauldron,
    ladle: LadleWrapper,
    witch: Witch,
    joinFactory: JoinFactory,
    poolFactory: PoolFactoryMock,
    wand: Wand,
    assets: Map<string, ERC20Mock>,
    oracles: Map<string, OracleMock>,
    series: Map<string, FYToken>,
    pools: Map<string, PoolMock>,
    joins: Map<string, Join>,
    vaults: Map<string, Map<string, string>>
  ) {
    this.owner = owner
    this.cauldron = cauldron
    this.ladle = ladle
    this.witch = witch
    this.joinFactory = joinFactory
    this.poolFactory = poolFactory
    this.wand = wand
    this.assets = assets
    this.oracles = oracles
    this.series = series
    this.pools = pools
    this.joins = joins
    this.vaults = vaults
  }

  public static async cauldronGovAuth(cauldron: Cauldron, receiver: string) {
    await cauldron.grantRoles(
      [
        id('addAsset(bytes6,address)'),
        id('addSeries(bytes6,bytes6,address)'),
        id('addIlks(bytes6,bytes6[])'),
        id('setDebtLimits(bytes6,bytes6,uint96,uint24,uint8)'),
        id('setRateOracle(bytes6,address)'),
        id('setSpotOracle(bytes6,bytes6,address,uint32)'),
      ],
      receiver
    )
  }

  public static async cauldronLadleAuth(cauldron: Cauldron, receiver: string) {
    await cauldron.grantRoles(
      [
        id('build(address,bytes12,bytes6,bytes6)'),
        id('destroy(bytes12)'),
        id('tweak(bytes12,bytes6,bytes6)'),
        id('give(bytes12,address)'),
        id('pour(bytes12,int128,int128)'),
        id('stir(bytes12,bytes12,uint128,uint128)'),
        id('roll(bytes12,bytes6,int128)'),
      ],
      receiver
    )
  }

  public static async cauldronWitchAuth(cauldron: Cauldron, receiver: string) {
    await cauldron.grantRoles(
      [id('give(bytes12,address)'), id('grab(bytes12,address)'), id('slurp(bytes12,uint128,uint128)')],
      receiver
    )
  }

  public static async ladleGovAuth(ladle: LadleWrapper, receiver: string) {
    await ladle.grantRoles(
      [
        id('addJoin(bytes6,address)'),
        id('addPool(bytes6,address)'),
        id('addModule(address,bool)'),
        id('setFee(uint256)'),
      ],
      receiver
    )
  }

  public static async wandAuth(wand: Wand, receiver: string) {
    await wand.grantRoles(
      [
        id('addAsset(bytes6,address)'),
        id('makeBase(bytes6,address,address,address)'),
        id('makeIlk(bytes6,bytes6,address,address,uint32,uint96,uint24,uint8)'),
        id('addSeries(bytes6,bytes6,uint32,bytes6[],string,string)'),
        id('addPool(bytes6,bytes6)'),
      ],
      receiver
    )
  }

  public static async witchGovAuth(witch: Witch, receiver: string) {
    await witch.grantRoles([id('setIlk(bytes6,uint32,uint64,uint128)')], receiver)
  }

  public static async joinFactoryAuth(joinFactory: JoinFactory, receiver: string) {
    await joinFactory.grantRoles([id('createJoin(address)')], receiver)
  }

  public static async fyTokenFactoryAuth(fyTokenFactory: FYTokenFactory, receiver: string) {
    await fyTokenFactory.grantRoles([id('createFYToken(bytes6,address,address,uint32,string,string)')], receiver)
  }

  // Initialize an asset for testing purposes. Gives the owner powers over it, and approves the join to take the asset from the owner.
  public static async initAsset(
    owner: SignerWithAddress,
    ladle: LadleWrapper,
    assetId: string,
    asset: ERC20Mock | DAIMock | USDCMock | WETH9Mock
  ): Promise<Join> {
    const join = (await ethers.getContractAt('Join', await ladle.joins(assetId), owner)) as Join
    await asset.approve(await ladle.joins(assetId), ethers.constants.MaxUint256) // Owner approves all joins to take from him. Only testing

    await join.grantRoles(
      [id('join(address,uint128)'), id('exit(address,uint128)'), id('retrieve(address,address)')],
      await owner.getAddress()
    ) // Only test environment

    return join
  }

  // Initialize a mock pool, with assets printed out of thin air. Also give the owner the right to mint fyToken at will.
  public static async initPool(owner: SignerWithAddress, pool: PoolMock, base: ERC20Mock, fyToken: FYToken) {
    await base.mint(pool.address, WAD.mul(1000000))
    await pool.mint(await owner.getAddress(), true, 0)
    await fyToken.grantRole(id('mint(address,uint256)'), await owner.getAddress()) // Only test environment
    await fyToken.mint(pool.address, WAD.mul(1100000))
    await pool.sync()

    return pool
  }

  // Set up a test environment. Provide at least one asset identifier.
  public static async setup(owner: SignerWithAddress, assetIds: Array<string>, seriesIds: Array<string>) {
    const ownerAdd = await owner.getAddress()
    const assets: Map<string, ERC20Mock> = new Map()
    const joins: Map<string, Join> = new Map()
    const oracles: Map<string, OracleMock> = new Map()
    const sources: Map<string, ISourceMock> = new Map()
    const series: Map<string, FYToken> = new Map()
    const pools: Map<string, PoolMock> = new Map()
    const vaults: Map<string, Map<string, string>> = new Map()

    // The first asset will be the underlying for all series
    // All assets after the first will be added as collateral for all series
    const baseId = assetIds[0]
    const ilkIds = assetIds.slice(1)

    // ==== Mocks ====

    // For each asset id passed as an argument, we create a Mock ERC20.
    // We also give 100000 tokens of that asset to the owner account.
    for (let assetId of assetIds) {
      const symbol = Buffer.from(assetId.slice(2), 'hex').toString('utf8')
      const asset = (await deployContract(owner, ERC20MockArtifact, [assetId, symbol])) as ERC20Mock
      await asset.mint(await owner.getAddress(), WAD.mul(100000))
      assets.set(assetId, asset)
    }
    const base = assets.get(baseId) as ERC20Mock
    const weth = (await deployContract(owner, WETH9MockArtifact, [])) as WETH9Mock
    const dai = (await deployContract(owner, DAIMockArtifact, [])) as DAIMock
    const usdc = (await deployContract(owner, USDCMockArtifact, [])) as USDCMock

    const cTokenRate = (await deployContract(owner, CTokenRateMockArtifact, [])) as ISourceMock
    await cTokenRate.set(WAD.mul(2).mul(10000000000))
    sources.set(RATE, cTokenRate)
    const cTokenChi = (await deployContract(owner, CTokenChiMockArtifact, [])) as ISourceMock
    await cTokenChi.set(WAD.mul(10000000000))
    sources.set(CHI, cTokenChi)

    for (let ilkId of ilkIds) {
      const aggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact, [8])) as ISourceMock
      await aggregator.set(WAD.mul(2))
      sources.set(ilkId, aggregator)
    }

    const ethAggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact, [8])) as ISourceMock
    await ethAggregator.set(WAD.mul(2))
    sources.set(ETH, ethAggregator)

    const daiAggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact, [8])) as ISourceMock
    await daiAggregator.set(WAD.mul(2))
    sources.set(DAI, daiAggregator)

    const usdcAggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact, [8])) as ISourceMock
    await usdcAggregator.set(WAD.mul(2))
    sources.set(USDC, usdcAggregator)

    // ==== Libraries ====
    const SafeERC20NamerFactory = await ethers.getContractFactory('SafeERC20Namer')
    const safeERC20NamerLibrary = ((await SafeERC20NamerFactory.deploy()) as unknown) as SafeERC20Namer
    await safeERC20NamerLibrary.deployed()

    // ==== Protocol ====

    const cauldron = (await deployContract(owner, CauldronArtifact, [])) as Cauldron
    const innerLadle = (await deployContract(owner, LadleArtifact, [cauldron.address, weth.address])) as Ladle
    const ladle = new LadleWrapper(innerLadle)
    const witch = (await deployContract(owner, WitchArtifact, [cauldron.address, ladle.address])) as Witch
    const joinFactory = (await deployContract(owner, JoinFactoryArtifact, [])) as JoinFactory
    const poolFactory = (await deployContract(owner, PoolFactoryMockArtifact, [])) as PoolFactoryMock

    const fyTokenFactoryFactory = await ethers.getContractFactory('FYTokenFactory', {
      libraries: {
        SafeERC20Namer: safeERC20NamerLibrary.address,
      },
    })
    const fyTokenFactory = ((await fyTokenFactoryFactory.deploy()) as unknown) as FYTokenFactory
    await fyTokenFactory.deployed()

    const wand = (await deployContract(owner, WandArtifact, [
      cauldron.address,
      ladle.address,
      witch.address,
      poolFactory.address,
      joinFactory.address,
      fyTokenFactory.address,
    ])) as Wand

    const chiRateOracle = (await deployContract(owner, CompoundMultiOracleArtifact, [])) as CompoundMultiOracle
    const spotOracle = (await deployContract(owner, ChainlinkMultiOracleArtifact, [])) as ChainlinkMultiOracle
    oracles.set(RATE, (chiRateOracle as unknown) as OracleMock)
    oracles.set(CHI, (chiRateOracle as unknown) as OracleMock)

    // ==== Orchestration ====
    await this.cauldronLadleAuth(cauldron, ladle.address)
    await this.cauldronWitchAuth(cauldron, witch.address)

    await this.cauldronGovAuth(cauldron, wand.address)
    await this.ladleGovAuth(ladle, wand.address)
    await this.witchGovAuth(witch, wand.address)
    await this.joinFactoryAuth(joinFactory, wand.address)
    await this.fyTokenFactoryAuth(fyTokenFactory, wand.address)
    await chiRateOracle.grantRole(id('setSource(bytes6,bytes6,address)'), wand.address)
    await spotOracle.grantRole(id('setSource(bytes6,bytes6,address)'), wand.address)

    // ==== Owner access (only test environment) ====
    await this.cauldronLadleAuth(cauldron, ownerAdd)
    await this.wandAuth(wand, ownerAdd)
    await this.joinFactoryAuth(joinFactory, ownerAdd)
    await this.fyTokenFactoryAuth(fyTokenFactory, ownerAdd)
    await this.cauldronGovAuth(cauldron, ownerAdd)
    await this.ladleGovAuth(ladle, ownerAdd)
    await this.witchGovAuth(witch, ownerAdd)

    // ==== Add assets and joins ====
    for (let assetId of assetIds) {
      const asset = assets.get(assetId) as ERC20Mock
      await wand.addAsset(assetId, asset.address)
      const joinAddress = (await joinFactory.queryFilter(joinFactory.filters.JoinCreated(asset.address, null)))[0]
        .args[1]
      const join = (await ethers.getContractAt('Join', joinAddress, owner)) as Join

      await this.initAsset(owner, ladle, assetId, asset)
      joins.set(assetId, join)
    }

    // Add WETH9
    await wand.addAsset(ETH, weth.address)
    const wethJoinAddress = (await joinFactory.queryFilter(joinFactory.filters.JoinCreated(weth.address, null)))[0]
      .args[1]
    const wethJoin = (await ethers.getContractAt('Join', wethJoinAddress, owner)) as Join

    await this.initAsset(owner, ladle, ETH, weth)
    assets.set(ETH, (weth as unknown) as ERC20Mock)
    joins.set(ETH, wethJoin)
    ilkIds.push(ETH)

    // Add Dai
    await wand.addAsset(DAI, dai.address)
    const daiJoinAddress = (await joinFactory.queryFilter(joinFactory.filters.JoinCreated(dai.address, null)))[0]
      .args[1]
    const daiJoin = (await ethers.getContractAt('Join', daiJoinAddress, owner)) as Join

    await this.initAsset(owner, ladle, DAI, dai)
    assets.set(DAI, (dai as unknown) as ERC20Mock)
    joins.set(DAI, daiJoin)
    ilkIds.push(DAI)

    // Add USDC
    await wand.addAsset(USDC, usdc.address)
    const usdcJoinAddress = (await joinFactory.queryFilter(joinFactory.filters.JoinCreated(usdc.address, null)))[0]
      .args[1]
    const usdcJoin = (await ethers.getContractAt('Join', usdcJoinAddress, owner)) as Join

    await this.initAsset(owner, ladle, USDC, usdc)
    assets.set(USDC, (usdc as unknown) as ERC20Mock)
    joins.set(USDC, usdcJoin)
    ilkIds.push(USDC)

    // ==== Make baseId the base, creating chi and rate oracles ====
    await wand.makeBase(baseId, chiRateOracle.address, cTokenRate.address, cTokenChi.address)

    // ==== Make ilkIds the ilks, creating spot oracles and settting debt limits ====
    const ratio = 1000000 //  1000000 == 100% collateralization ratio
    const max = WAD
    const min = 1000000
    const dec = 6
    for (let ilkId of ilkIds) {
      const source = sources.get(ilkId) as ISourceMock
      await wand.makeIlk(baseId, ilkId, spotOracle.address, source.address, ratio, max, min, dec)
      oracles.set(ilkId, (spotOracle as unknown) as OracleMock)
    }

    // ==== Add series and pools ====
    // For each series identifier we create a fyToken with the first asset as underlying.
    // The maturities for the fyTokens are in three month intervals, starting three months from now

    const { timestamp } = await ethers.provider.getBlock('latest')
    let count: number = 1
    for (let seriesId of seriesIds) {
      const maturity = timestamp + THREE_MONTHS * count++
      await wand.addSeries(seriesId, baseId, maturity, ilkIds, seriesId, seriesId)
      const fyToken = (await ethers.getContractAt(
        'FYToken',
        (await cauldron.series(seriesId)).fyToken,
        owner
      )) as FYToken
      const pool = (await ethers.getContractAt('PoolMock', await ladle.pools(seriesId), owner)) as PoolMock
      await this.initPool(owner, pool, base, fyToken)
      series.set(seriesId, fyToken)
      pools.set(seriesId, pool)

      await fyToken.grantRoles(
        [id('mint(address,uint256)'), id('burn(address,uint256)'), id('setOracle(address)')],
        ownerAdd
      ) // Only test environment
    }

    // ==== Build some vaults ====
    // For each series and ilk we create a vault - vaults[seriesId][ilkId] = vaultId
    for (let seriesId of seriesIds) {
      const seriesVaults: Map<string, string> = new Map()
      for (let ilkId of ilkIds) {
        await ladle.build(seriesId, ilkId)
        seriesVaults.set(ilkId, await getLastVaultId(cauldron))
      }
      vaults.set(seriesId, seriesVaults)
    }

    return new YieldEnvironment(
      owner,
      cauldron,
      ladle,
      witch,
      joinFactory,
      poolFactory,
      wand,
      assets,
      oracles,
      series,
      pools,
      joins,
      vaults
    )
  }
}
