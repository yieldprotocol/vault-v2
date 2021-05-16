import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { BaseProvider } from '@ethersproject/providers'
import { id } from '@yield-protocol/utils-v2'
import { constants } from '@yield-protocol/utils-v2'
const { WAD, THREE_MONTHS, ETH, DAI, USDC } = constants
import { CHI, RATE } from '../../src/constants'

import CauldronArtifact from '../../artifacts/contracts/Cauldron.sol/Cauldron.json'
import JoinArtifact from '../../artifacts/contracts/Join.sol/Join.json'
import LadleArtifact from '../../artifacts/contracts/Ladle.sol/Ladle.json'
import WandArtifact from '../../artifacts/contracts/Wand.sol/Wand.json'
import WitchArtifact from '../../artifacts/contracts/Witch.sol/Witch.json'
import JoinFactoryArtifact from '../../artifacts/contracts/JoinFactory.sol/JoinFactory.json'
import FYTokenArtifact from '../../artifacts/contracts/FYToken.sol/FYToken.json'
import PoolMockArtifact from '../../artifacts/contracts/mocks/PoolMock.sol/PoolMock.json'

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
import { Ladle } from '../../typechain/Ladle'
import { Wand } from '../../typechain/Wand'
import { Witch } from '../../typechain/Witch'
import { JoinFactory } from '../../typechain/JoinFactory'
import { FYToken } from '../../typechain/FYToken'
import { PoolMock } from '../../typechain/PoolMock'

import { OracleMock } from '../../typechain/OracleMock'
import { ChainlinkMultiOracle } from '../../typechain/ChainlinkMultiOracle'
import { CompoundMultiOracle } from '../../typechain/CompoundMultiOracle'
import { SourceMock } from '../../typechain/SourceMock'

import { ERC20Mock } from '../../typechain/ERC20Mock'
import { WETH9Mock } from '../../typechain/WETH9Mock'
import { DAIMock } from '../../typechain/DAIMock'
import { USDCMock } from '../../typechain/USDCMock'

import { LadleWrapper } from '../../src/ladleWrapper'

import { ethers, waffle } from 'hardhat'
const { deployContract } = waffle

export class YieldEnvironment {
  owner: SignerWithAddress
  cauldron: Cauldron
  ladle: LadleWrapper
  witch: Witch
  joinFactory: JoinFactory
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
        id('setAuctionInterval(uint32)'),
        id('addAsset(bytes6,address)'),
        id('addSeries(bytes6,bytes6,address)'),
        id('addIlks(bytes6,bytes6[])'),
        id('setMaxDebt(bytes6,bytes6,uint128)'),
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
        id('slurp(bytes12,uint128,uint128)'),
      ],
      receiver
    )
  }

  public static async cauldronWitchAuth(cauldron: Cauldron, receiver: string) {
    await cauldron.grantRoles(
      [
        id('give(bytes12,address)'),
        id('grab(bytes12,address)'),
      ],
      receiver
    )
  }

  public static async ladleGovAuth(ladle: LadleWrapper, receiver: string) {
    await ladle.grantRoles(
      [
        id('addJoin(bytes6,address)'),
        id('addPool(bytes6,address)'),
        id('setModule(address,bool)'),
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
        id('makeIlk(bytes6,bytes6,address,address,uint32,uint128)'),
        id('addSeries(bytes6,bytes6,uint32,bytes6[],string,string)'),
      ],
      receiver
    )
  }

  public static async ladleWitchAuth(ladle: LadleWrapper, receiver: string) {
    await ladle.grantRoles([
      id(
        'settle(bytes12,address,uint128,uint128)'
      )],
      receiver
    )
  }

  public static async witchGovAuth(witch: Witch, receiver: string) {
    await witch.grantRoles(
      [
        id('setAuctionTime(uint128)'),
        id('setInitialProportion(uint128)'),
      ],
      receiver
    )
  }

  public static async addAsset(owner: SignerWithAddress, ladle: LadleWrapper, wand: Wand, assetId: string, asset: ERC20Mock | DAIMock | USDCMock | WETH9Mock): Promise<Join> {
    await wand.addAsset(assetId, asset.address)

    const join = await ethers.getContractAt('Join', await ladle.joins(assetId), owner) as Join
    await asset.approve(await ladle.joins(assetId), ethers.constants.MaxUint256) // Owner approves all joins to take from him. Only testing

    await join.grantRoles([
      id('join(address,uint128)'),
      id('exit(address,uint128)'),
      id('retrieve(address,address)')
    ], await owner.getAddress()) // Only test environment

    return join
  }

  public static async addSeries(
    owner: SignerWithAddress,
    cauldron: Cauldron,
    ladle: LadleWrapper,
    baseJoin: Join,
    chiOracle: CompoundMultiOracle,
    seriesId: string,
    baseId: string,
    ilkIds: Array<string>,
    maturity: number,

  ) {
    const fyToken = (await deployContract(owner, FYTokenArtifact, [
      baseId,
      chiOracle.address,
      baseJoin.address,
      maturity,
      seriesId,
      seriesId,
    ])) as FYToken
    await cauldron.addSeries(seriesId, baseId, fyToken.address)

    // Add all ilks to each series
    await cauldron.addIlks(seriesId, ilkIds)

    await baseJoin.grantRoles([id('join(address,uint128)'), id('exit(address,uint128)')], fyToken.address)
    await fyToken.grantRoles([id('mint(address,uint256)'), id('burn(address,uint256)')], ladle.address)
    return fyToken
  }

  public static async addPool(
    owner: SignerWithAddress,
    ladle: LadleWrapper,
    base: ERC20Mock,
    fyToken: FYToken,
    seriesId: string,
  ) {
    const pool = (await deployContract(owner, PoolMockArtifact, [
      base.address,
      fyToken.address,
    ])) as PoolMock

    // Initialize pool
    await base.mint(pool.address, WAD.mul(1000000))
    await pool.mint(await owner.getAddress(), true, 0)
    await fyToken.mint(pool.address, WAD.mul(1100000))
    await pool.sync()

    await ladle.addPool(seriesId, pool.address)

    return pool
  }

  // Set up a test environment. Provide at least one asset identifier.
  public static async setup(owner: SignerWithAddress, assetIds: Array<string>, seriesIds: Array<string>) {
    const ownerAdd = await owner.getAddress()
    const assets: Map<string, ERC20Mock> = new Map()
    const joins: Map<string, Join> = new Map()
    const oracles: Map<string, OracleMock> = new Map()
    const sources: Map<string, SourceMock> = new Map()
    const series: Map<string, FYToken> = new Map()
    const pools: Map<string, PoolMock> = new Map()
    const vaults: Map<string, Map<string, string>> = new Map()
    const ilkIds = assetIds.slice(1)
    const baseId = assetIds[0]

    // ==== Mocks ====

    // For each asset id passed as an argument, we create a Mock ERC20.
    // We also give 100000 tokens of that asset to the owner account.
    for (let assetId of assetIds) {
      const symbol = Buffer.from(assetId.slice(2), 'hex').toString('utf8')
      const asset = (await deployContract(owner, ERC20MockArtifact, [assetId, symbol])) as ERC20Mock
      await asset.mint(await owner.getAddress(), WAD.mul(100000))
      assets.set(assetId, asset)
    }
    const weth = (await deployContract(owner, WETH9MockArtifact, [])) as WETH9Mock
    const dai = (await deployContract(owner, DAIMockArtifact, [])) as DAIMock
    const usdc = (await deployContract(owner, USDCMockArtifact, [])) as USDCMock

    const cTokenRate = (await deployContract(owner, CTokenRateMockArtifact, [])) as SourceMock
    await cTokenRate.set(WAD.mul(2))
    sources.set(RATE, cTokenRate)
    const cTokenChi = (await deployContract(owner, CTokenChiMockArtifact, [])) as SourceMock
    await cTokenChi.set(WAD)
    sources.set(CHI, cTokenChi)

    for (let ilkId of ilkIds) {
      const aggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact, [8])) as SourceMock
      await aggregator.set(WAD.mul(2))
      sources.set(ilkId, aggregator)
    }

    const ethAggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact, [8])) as SourceMock
    await ethAggregator.set(WAD.mul(2))
    sources.set(ETH, ethAggregator)

    const daiAggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact, [8])) as SourceMock
    await daiAggregator.set(WAD.mul(2))
    sources.set(DAI, daiAggregator)

    const usdcAggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact, [8])) as SourceMock
    await usdcAggregator.set(WAD.mul(2))
    sources.set(USDC, usdcAggregator)

    // ==== Protocol ====

    const cauldron = (await deployContract(owner, CauldronArtifact, [])) as Cauldron
    const innerLadle = (await deployContract(owner, LadleArtifact, [cauldron.address])) as Ladle
    const ladle = new LadleWrapper(innerLadle)
    const witch = (await deployContract(owner, WitchArtifact, [cauldron.address, ladle.address])) as Witch
    const joinFactory = (await deployContract(owner, JoinFactoryArtifact, [])) as JoinFactory
    const wand = (await deployContract(owner, WandArtifact, [cauldron.address, ladle.address, cauldron.address, joinFactory.address])) as Wand // TODO: Get a PoolFactoryMock going
    const chiRateOracle = (await deployContract(owner, CompoundMultiOracleArtifact, [])) as CompoundMultiOracle
    const spotOracle = (await deployContract(owner, ChainlinkMultiOracleArtifact, [])) as ChainlinkMultiOracle
    oracles.set(RATE, chiRateOracle as unknown as OracleMock)
    oracles.set(CHI, chiRateOracle as unknown as OracleMock)

    // ==== Orchestration ====
    await this.cauldronLadleAuth(cauldron, ladle.address)
    await this.cauldronWitchAuth(cauldron, witch.address)
    await this.ladleWitchAuth(ladle, witch.address)
  
    await this.cauldronGovAuth(cauldron, wand.address)
    await this.ladleGovAuth(ladle, wand.address)
    await this.witchGovAuth(witch, wand.address)
    await chiRateOracle.transferOwnership(wand.address)
    await spotOracle.transferOwnership(wand.address)

    // ==== Owner access (only test environment) ====
    await this.wandAuth(wand, ownerAdd)

    await this.cauldronLadleAuth(cauldron, ownerAdd)
    await this.ladleWitchAuth(ladle, ownerAdd)

    await this.cauldronGovAuth(cauldron, ownerAdd)
    await this.ladleGovAuth(ladle, ownerAdd)
    await this.witchGovAuth(witch, ownerAdd)

    // ==== Set protection period for vaults in liquidation ====
    await cauldron.setAuctionInterval(24 * 60 * 60)

    // ==== Add assets and joins ====
    for (let assetId of assetIds) {
      const join = await this.addAsset(owner, ladle, wand, assetId, assets.get(assetId) as ERC20Mock)
      joins.set(assetId, join)
    }

    // The first asset will be the underlying for all series
    // All assets after the first will be added as collateral for all series
    const base = assets.get(baseId) as ERC20Mock
    const baseJoin = joins.get(baseId) as Join

    // Add WETH9
    const wethJoin = await this.addAsset(owner, ladle, wand, ETH, weth)

    assets.set(ETH, weth as unknown as ERC20Mock)
    joins.set(ETH, wethJoin)
    ilkIds.push(ETH)

    // Add Dai
    const daiJoin = await this.addAsset(owner, ladle, wand, DAI, dai)

    assets.set(DAI, dai as unknown as ERC20Mock)
    joins.set(DAI, daiJoin)
    ilkIds.push(DAI)

    // Add USDC
    const usdcJoin = await this.addAsset(owner, ladle, wand, USDC, usdc)

    assets.set(USDC, usdc as unknown as ERC20Mock)
    joins.set(USDC, usdcJoin)
    ilkIds.push(USDC)

    // ==== Make baseId the base, creating chi and rate oracles ====
    await wand.makeBase(baseId, chiRateOracle.address, cTokenRate.address, cTokenChi.address)

    // ==== Make ilkIds the ilks, creating spot oracles and settting debt limits ====
    const ratio = 1000000 //  1000000 == 100% collateralization ratio
    const maxDebt = WAD.mul(1000000)
    for (let ilkId of ilkIds) {
      const source = sources.get(ilkId) as SourceMock
      await wand.makeIlk(baseId, ilkId, spotOracle.address, source.address, ratio, maxDebt)
      oracles.set(ilkId, spotOracle as unknown as OracleMock)
    }

    // ==== Add series and pools ====
    // For each series identifier we create a fyToken with the first asset as underlying.
    // The maturities for the fyTokens are in three month intervals, starting three months from now

    const provider: BaseProvider = await ethers.provider
    const now = (await provider.getBlock(await provider.getBlockNumber())).timestamp
    let count: number = 1
    for (let seriesId of seriesIds) {
      const maturity = now + THREE_MONTHS * count++
      const fyToken = await this.addSeries(owner, cauldron, ladle, baseJoin, chiRateOracle, seriesId, baseId, ilkIds, maturity) as FYToken
      series.set(seriesId, fyToken)
      await fyToken.grantRoles([
          id('mint(address,uint256)'),
          id('burn(address,uint256)'),
          id('setOracle(address)')],
        ownerAdd) // Only test environment

      // Add a pool between the base and each series
      pools.set(seriesId, await this.addPool(owner, ladle, base, fyToken, seriesId))
    }

    // ==== Build some vaults ====
    // For each series and ilk we create a vault - vaults[seriesId][ilkId] = vaultId
    for (let seriesId of seriesIds) {
      const seriesVaults: Map<string, string> = new Map()
      for (let ilkId of ilkIds) {
        await cauldron.build(ownerAdd, ethers.utils.hexlify(ethers.utils.randomBytes(12)), seriesId, ilkId)
        const vaultEvents = (await cauldron.queryFilter(cauldron.filters.VaultBuilt(null, null, null, null)))
        const vaultId = vaultEvents[vaultEvents.length - 1].args.vaultId
        seriesVaults.set(ilkId, vaultId)
      }
      vaults.set(seriesId, seriesVaults)
    }

    return new YieldEnvironment(owner, cauldron, ladle, witch, joinFactory, wand, assets, oracles, series, pools, joins, vaults)
  }
}
