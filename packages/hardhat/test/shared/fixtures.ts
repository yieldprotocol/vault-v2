import { id, constants } from '@yield-protocol/utils-v2'

import { sendStatic } from './helpers'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

const { WAD, THREE_MONTHS } = constants
import { CHI, RATE, ETH, DAI, USDC } from '../../src/constants'

import CauldronArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/Cauldron.sol/Cauldron.json'
import LadleArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/Ladle.sol/Ladle.json'
import WandArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/deprecated/Wand.sol/Wand.json'
import WitchOldArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/deprecated/WitchOld.sol/WitchOld.json'
import JoinFactoryArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/deprecated/JoinFactoryMock.sol/JoinFactoryMock.json'
import PoolFactoryMockArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/deprecated/PoolFactoryMock.sol/PoolFactoryMock.json'

import ChainlinkMultiOracleArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/oracles/chainlink/ChainlinkMultiOracle.sol/ChainlinkMultiOracle.json'
import CompoundMultiOracleArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/oracles/compound/CompoundMultiOracle.sol/CompoundMultiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import CTokenRateMockArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/mocks/oracles/compound/CTokenRateMock.sol/CTokenRateMock.json'
import CTokenChiMockArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/mocks/oracles/compound/CTokenChiMock.sol/CTokenChiMock.json'

import ERC20MockArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import WETH9MockArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import DAIMockArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/mocks/DAIMock.sol/DAIMock.json'
import USDCMockArtifact from '../../artifacts/@yield-protocol/vault-v2/contracts/mocks/USDCMock.sol/USDCMock.json'

import { Cauldron } from '../../typechain/Cauldron'
import { Join } from '../../typechain/Join'
import { FYToken } from '../../typechain/FYToken'
import { Ladle } from '../../typechain/Ladle'
import { WitchOld } from '../../typechain/WitchOld'
import { IJoinFactory } from '../../typechain/IJoinFactory'
import { IFYTokenFactory } from '../../typechain/IFYTokenFactory'
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
  witch: WitchOld
  joinFactory: IJoinFactory
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
    witch: WitchOld,
    joinFactory: IJoinFactory,
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
        id(cauldron.interface, 'addAsset(bytes6,address)'),
        id(cauldron.interface, 'addSeries(bytes6,bytes6,address)'),
        id(cauldron.interface, 'addIlks(bytes6,bytes6[])'),
        id(cauldron.interface, 'setDebtLimits(bytes6,bytes6,uint96,uint24,uint8)'),
        id(cauldron.interface, 'setLendingOracle(bytes6,address)'),
        id(cauldron.interface, 'setSpotOracle(bytes6,bytes6,address,uint32)'),
      ],
      receiver
    )
  }

  public static async cauldronLadleAuth(cauldron: Cauldron, receiver: string) {
    await cauldron.grantRoles(
      [
        id(cauldron.interface, 'build(address,bytes12,bytes6,bytes6)'),
        id(cauldron.interface, 'destroy(bytes12)'),
        id(cauldron.interface, 'tweak(bytes12,bytes6,bytes6)'),
        id(cauldron.interface, 'give(bytes12,address)'),
        id(cauldron.interface, 'pour(bytes12,int128,int128)'),
        id(cauldron.interface, 'stir(bytes12,bytes12,uint128,uint128)'),
        id(cauldron.interface, 'roll(bytes12,bytes6,int128)'),
      ],
      receiver
    )
  }

  public static async cauldronWitchOldAuth(cauldron: Cauldron, receiver: string) {
    await cauldron.grantRoles(
      [id(cauldron.interface, 'give(bytes12,address)'), id(cauldron.interface, 'slurp(bytes12,uint128,uint128)')],
      receiver
    )
  }

  public static async ladleGovAuth(ladle: LadleWrapper, receiver: string) {
    await ladle.grantRoles(
      [
        id(ladle.ladle.interface, 'addJoin(bytes6,address)'),
        id(ladle.ladle.interface, 'addPool(bytes6,address)'),
        id(ladle.ladle.interface, 'addModule(address,bool)'),
        id(ladle.ladle.interface, 'setFee(uint256)'),
      ],
      receiver
    )
  }

  public static async wandAuth(wand: Wand, receiver: string) {
    await wand.grantRoles(
      [
        id(wand.interface, 'addAsset(bytes6,address)'),
        id(wand.interface, 'makeBase(bytes6,address)'),
        id(wand.interface, 'makeIlk(bytes6,bytes6,address,uint32,uint96,uint24,uint8)'),
        id(wand.interface, 'addSeries(bytes6,bytes6,uint32,bytes6[],string,string)'),
      ],
      receiver
    )
  }

  public static async witchGovAuth(witch: WitchOld, receiver: string) {
    await witch.grantRoles(
      [
        id(witch.interface, 'point(bytes32,address)'),
        id(witch.interface, 'setIlk(bytes6,uint32,uint64,uint96,uint24,uint8)'),
      ],
      receiver
    )
  }

  public static async joinFactoryAuth(joinFactory: IJoinFactory, receiver: string) {
    await joinFactory.grantRoles([id(joinFactory.interface, 'createJoin(address)')], receiver)
  }

  public static async fyTokenFactoryAuth(fyTokenFactory: IFYTokenFactory, receiver: string) {
    await fyTokenFactory.grantRoles(
      [id(fyTokenFactory.interface, 'createFYToken(bytes6,address,address,uint32,string,string)')],
      receiver
    )
  }

  // Initialize an asset for testing purposes. Gives the owner powers over it, and approves the join to take the asset from the owner.
  public static async initAsset(
    owner: SignerWithAddress,
    ladle: LadleWrapper,
    assetId: string,
    asset: ERC20Mock | DAIMock | USDCMock | WETH9Mock
  ): Promise<Join> {
    const join = (await ethers.getContractAt('FlashJoin', await ladle.joins(assetId), owner)) as Join
    await asset.approve(await ladle.joins(assetId), ethers.constants.MaxUint256) // Owner approves all joins to take from him. Only testing

    await join.grantRoles(
      [
        id(join.interface, 'join(address,uint128)'),
        id(join.interface, 'exit(address,uint128)'),
        id(join.interface, 'retrieve(address,address)'),
      ],
      await owner.getAddress()
    ) // Only test environment

    await asset.mint(await owner.getAddress(), WAD.mul(100000))

    return join
  }

  // Initialize a mock pool, with assets printed out of thin air. Also give the owner the right to mint fyToken at will.
  public static async initPool(owner: SignerWithAddress, pool: PoolMock, base: ERC20Mock, fyToken: FYToken) {
    await base.mint(pool.address, WAD.mul(1000000))
    await pool.mint(await owner.getAddress(), true, 0)
    await fyToken.grantRole(id(fyToken.interface, 'mint(address,uint256)'), await owner.getAddress()) // Only test environment
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
    // If the user didn't specify ETH as an ilk, we add it anyway
    if (assetIds.indexOf(ETH) == -1) assetIds.push(ETH)
    const baseId = assetIds[0]
    const ilkIds = assetIds.slice(1)

    // ==== Mocks ====

    const weth = (await deployContract(owner, WETH9MockArtifact, [])) as WETH9Mock
    const dai = (await deployContract(owner, DAIMockArtifact, [])) as DAIMock
    const usdc = (await deployContract(owner, USDCMockArtifact, [])) as USDCMock

    // For each asset id passed as an argument, we create a Mock ERC20.
    // We also give 100000 tokens of that asset to the owner account.
    for (let assetId of assetIds) {
      const symbol = Buffer.from(assetId.slice(2), 'hex').toString('utf8')
      let asset: ERC20Mock
      if (assetId === DAI) asset = dai as unknown as ERC20Mock
      else if (assetId === USDC) asset = usdc as unknown as ERC20Mock
      else if (assetId === ETH) asset = weth as unknown as ERC20Mock
      else asset = (await deployContract(owner, ERC20MockArtifact, [assetId, symbol])) as ERC20Mock

      assets.set(assetId, asset)
    }
    const base = assets.get(baseId) as ERC20Mock

    const cTokenRate = (await deployContract(owner, CTokenRateMockArtifact, [])) as ISourceMock
    await cTokenRate.set(WAD.mul(2).mul(10000000000))
    sources.set(RATE, cTokenRate)
    const cTokenChi = (await deployContract(owner, CTokenChiMockArtifact, [])) as ISourceMock
    await cTokenChi.set(WAD.mul(10000000000))
    sources.set(CHI, cTokenChi)

    for (let ilkId of ilkIds) {
      const aggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact)) as ISourceMock
      await aggregator.set(WAD.div(2))
      sources.set(ilkId, aggregator)
    }

    const ethAggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact)) as ISourceMock
    await ethAggregator.set(WAD.div(2))
    sources.set(ETH, ethAggregator)

    const daiAggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact)) as ISourceMock
    await daiAggregator.set(WAD.div(2))
    sources.set(DAI, daiAggregator)

    const usdcAggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact)) as ISourceMock
    await usdcAggregator.set(WAD.div(2))
    sources.set(USDC, usdcAggregator)

    const baseAggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact)) as ISourceMock
    await baseAggregator.set(WAD)
    sources.set(baseId, baseAggregator)

    // ==== Libraries ====
    const SafeERC20NamerFactory = await ethers.getContractFactory('SafeERC20Namer')
    const safeERC20NamerLibrary = (await SafeERC20NamerFactory.deploy()) as unknown as SafeERC20Namer
    await safeERC20NamerLibrary.deployed()

    // ==== Protocol ====

    const cauldron = (await deployContract(owner, CauldronArtifact, [])) as Cauldron
    const innerLadle = (await deployContract(owner, LadleArtifact, [cauldron.address, weth.address])) as Ladle
    const ladle = new LadleWrapper(innerLadle)
    const witch = (await deployContract(owner, WitchOldArtifact, [cauldron.address, ladle.address])) as WitchOld
    const joinFactory = (await deployContract(owner, JoinFactoryArtifact, [])) as IJoinFactory
    const poolFactory = (await deployContract(owner, PoolFactoryMockArtifact, [])) as PoolFactoryMock

    const fyTokenFactoryFactory = await ethers.getContractFactory('FYTokenFactoryMock', {
      libraries: {
        SafeERC20Namer: safeERC20NamerLibrary.address,
      },
    })
    const fyTokenFactory = (await fyTokenFactoryFactory.deploy()) as unknown as IFYTokenFactory
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
    oracles.set(RATE, chiRateOracle as unknown as OracleMock)
    oracles.set(CHI, chiRateOracle as unknown as OracleMock)

    // ==== Orchestration ====
    await this.cauldronLadleAuth(cauldron, ladle.address)
    await this.cauldronWitchOldAuth(cauldron, witch.address)

    await this.cauldronGovAuth(cauldron, wand.address)
    await this.ladleGovAuth(ladle, wand.address)
    await this.witchGovAuth(witch, wand.address)
    await this.joinFactoryAuth(joinFactory, wand.address)
    await this.fyTokenFactoryAuth(fyTokenFactory, wand.address)
    await chiRateOracle.grantRole(id(chiRateOracle.interface, 'setSource(bytes6,bytes6,address)'), wand.address)
    await spotOracle.grantRole(
      id(spotOracle.interface, 'setSource(bytes6,address,bytes6,address,address)'),
      wand.address
    )

    // ==== Owner access (only test environment) ====
    await this.cauldronLadleAuth(cauldron, ownerAdd)
    await this.wandAuth(wand, ownerAdd)
    await this.joinFactoryAuth(joinFactory, ownerAdd)
    await this.fyTokenFactoryAuth(fyTokenFactory, ownerAdd)
    await this.cauldronGovAuth(cauldron, ownerAdd)
    await this.ladleGovAuth(ladle, ownerAdd)
    await this.witchGovAuth(witch, ownerAdd)
    await chiRateOracle.grantRole(id(chiRateOracle.interface, 'setSource(bytes6,bytes6,address)'), ownerAdd)
    await spotOracle.grantRole(id(spotOracle.interface, 'setSource(bytes6,address,bytes6,address,address)'), ownerAdd)

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

    // ==== Make baseId the base, creating chi and rate oracles ====
    await chiRateOracle.setSource(baseId, RATE, cTokenRate.address)
    await chiRateOracle.setSource(baseId, CHI, cTokenChi.address)
    await wand.makeBase(baseId, chiRateOracle.address)

    // ==== Make ilkIds the ilks, creating spot oracles and settting debt limits ====
    const ratio = 1000000 //  1000000 == 100% collateralization ratio
    for (let ilkId of assetIds) {
      // Including ilkId == baseId
      const spotSource = sources.get(ilkId) as ISourceMock
      const base = assets.get(baseId) as ERC20Mock
      const ilk = assets.get(ilkId) as ERC20Mock
      await spotOracle.setSource(baseId, base.address, ilkId, ilk.address, spotSource.address)
      await witch.setIlk(ilkId, 4 * 60 * 60, WAD.div(2), 1000000, 0, await ilk.decimals())
      await wand.makeIlk(baseId, ilkId, spotOracle.address, ratio, 1000000, 1, await base.decimals())
      oracles.set(ilkId, spotOracle as unknown as OracleMock)
    }

    // ==== Add series and pools ====
    // For each series identifier we create a fyToken with the first asset as underlying.
    // The maturities for the fyTokens are in three month intervals, starting three months from now

    const { timestamp } = await ethers.provider.getBlock('latest')
    let count: number = 1
    for (let seriesId of seriesIds) {
      const maturity = timestamp + THREE_MONTHS * count++
      await wand.addSeries(seriesId, baseId, maturity, assetIds, seriesId, seriesId)
      const fyToken = (await ethers.getContractAt(
        'FYToken',
        (
          await cauldron.series(seriesId)
        ).fyToken,
        owner
      )) as FYToken
      const pool = (await ethers.getContractAt('PoolMock', await ladle.pools(seriesId), owner)) as PoolMock
      await this.initPool(owner, pool, base, fyToken)
      series.set(seriesId, fyToken)
      pools.set(seriesId, pool)

      await fyToken.grantRoles(
        [
          id(fyToken.interface, 'mint(address,uint256)'),
          id(fyToken.interface, 'burn(address,uint256)'),
          id(fyToken.interface, 'point(bytes32,address)'),
          id(fyToken.interface, 'setFlashFeeFactor(uint256)'),
        ],
        ownerAdd
      ) // Only test environment
    }

    // ==== Build some vaults ====
    // For each series and ilk we create a vault - vaults[seriesId][ilkId] = vaultId
    for (let seriesId of seriesIds) {
      const seriesVaults: Map<string, string> = new Map()
      for (let ilkId of assetIds) {
        // Including a vault whose ilk equals its base
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
