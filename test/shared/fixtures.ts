import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { BaseProvider } from '@ethersproject/providers'
import { id } from '@yield-protocol/utils-v2'
import { constants } from '@yield-protocol/utils-v2'
const { WAD, THREE_MONTHS, ETH, DAI, USDC } = constants

import CauldronArtifact from '../../artifacts/contracts/Cauldron.sol/Cauldron.json'
import JoinArtifact from '../../artifacts/contracts/Join.sol/Join.json'
import LadleArtifact from '../../artifacts/contracts/Ladle.sol/Ladle.json'
import WitchArtifact from '../../artifacts/contracts/Witch.sol/Witch.json'
import FYTokenArtifact from '../../artifacts/contracts/FYToken.sol/FYToken.json'
import PoolMockArtifact from '../../artifacts/contracts/mocks/PoolMock.sol/PoolMock.json'

import ChainlinkOracleArtifact from '../../artifacts/contracts/oracles/ChainlinkOracle.sol/ChainlinkOracle.json'
import CompoundRateOracleArtifact from '../../artifacts/contracts/oracles/CompoundRateOracle.sol/CompoundRateOracle.json'
import CompoundChiOracleArtifact from '../../artifacts/contracts/oracles/CompoundChiOracle.sol/CompoundChiOracle.json'
import ChainlinkAggregatorV3MockArtifact from '../../artifacts/contracts/mocks/ChainlinkAggregatorV3Mock.sol/ChainlinkAggregatorV3Mock.json'
import CTokenRateMockArtifact from '../../artifacts/contracts/mocks/CTokenRateMock.sol/CTokenRateMock.json'
import CTokenChiMockArtifact from '../../artifacts/contracts/mocks/CTokenChiMock.sol/CTokenChiMock.json'

import ERC20MockArtifact from '../../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import WETH9MockArtifact from '../../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import DAIMockArtifact from '../../artifacts/contracts/mocks/DAIMock.sol/DAIMock.json'
import USDCMockArtifact from '../../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'

import { Cauldron } from '../../typechain/Cauldron'
import { Join } from '../../typechain/Join'
import { Ladle } from '../../typechain/Ladle'
import { Witch } from '../../typechain/Witch'
import { FYToken } from '../../typechain/FYToken'
import { PoolMock } from '../../typechain/PoolMock'

import { OracleMock } from '../../typechain/OracleMock'
import { ChainlinkAggregatorV3Mock } from '../../typechain/ChainlinkAggregatorV3Mock'
import { CTokenRateMock } from '../../typechain/CTokenRateMock'
import { CTokenChiMock } from '../../typechain/CTokenChiMock'

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
        id('destroy(bytes12)'),
        id('grab(bytes12)'),
      ],
      receiver
    )
  }

  public static async ladleGovAuth(ladle: LadleWrapper, receiver: string) {
    await ladle.grantRoles(
      [
        id('addJoin(bytes6,address)'),
        id('addPool(bytes6,address)'),
        id('setPoolRouter(address)'),
        id('setFee(uint256)'),
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

  public static async addAsset(owner: SignerWithAddress, cauldron: Cauldron, assetId: string) {
    const symbol = Buffer.from(assetId.slice(2), 'hex').toString('utf8')
    const asset = (await deployContract(owner, ERC20MockArtifact, [assetId, symbol])) as ERC20Mock
    await cauldron.addAsset(assetId, asset.address)
    await asset.mint(await owner.getAddress(), WAD.mul(100000))
    return asset
  }

  public static async addJoin(owner: SignerWithAddress, ladle: LadleWrapper, asset: ERC20Mock, assetId: string) {
    const join = (await deployContract(owner, JoinArtifact, [asset.address])) as Join
    await ladle.addJoin(assetId, join.address)
    await asset.approve(join.address, ethers.constants.MaxUint256) // Owner approves all joins to take from him. Only testing
    await join.grantRoles([id('join(address,uint128)'), id('exit(address,uint128)')], ladle.address)
    return join
  }

  public static async addSpotOracle(owner: SignerWithAddress, cauldron: Cauldron, baseId: string, ilkId: string) {
    const ratio = 1000000 //  1000000 == 100% collateralization ratio
    const aggregator = (await deployContract(owner, ChainlinkAggregatorV3MockArtifact, [])) as ChainlinkAggregatorV3Mock
    const oracle = (await deployContract(owner, ChainlinkOracleArtifact, [aggregator.address])) as OracleMock // Externally, all oracles are the same
    await aggregator.set(WAD.mul(2))
    await cauldron.setSpotOracle(baseId, ilkId, oracle.address, ratio)
    return oracle
  }

  public static async addRateOracle(owner: SignerWithAddress, cauldron: Cauldron, baseId: string) {
    const ctoken = (await deployContract(owner, CTokenRateMockArtifact, [])) as CTokenRateMock
    const oracle = (await deployContract(owner, CompoundRateOracleArtifact, [ctoken.address])) as OracleMock // Externally, all oracles are the same
    await ctoken.set(WAD.mul(2))
    await cauldron.setRateOracle(baseId, oracle.address)
    return oracle
  }

  public static async addChiOracle(owner: SignerWithAddress) { // This will be referenced by the fyToken, and needs no id
    const ctoken = (await deployContract(owner, CTokenChiMockArtifact, [])) as CTokenChiMock
    const oracle = (await deployContract(owner, CompoundChiOracleArtifact, [ctoken.address])) as OracleMock // Externally, all oracles are the same
    await ctoken.set(WAD)
    return oracle
  }

  public static async addSeries(
    owner: SignerWithAddress,
    cauldron: Cauldron,
    ladle: LadleWrapper,
    baseJoin: Join,
    chiOracle: OracleMock,
    seriesId: string,
    baseId: string,
    ilkIds: Array<string>,
    maturity: number,

  ) {
    const fyToken = (await deployContract(owner, FYTokenArtifact, [
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

    // Initialize pool with a million tokens of each
    await fyToken.mint(pool.address, WAD.mul(1000000))
    await base.mint(pool.address, WAD.mul(1000000))
    await pool.sync()

    await ladle.addPool(seriesId, pool.address)

    return pool
  }

  // Set up a test environment. Provide at least one asset identifier.
  public static async setup(owner: SignerWithAddress, assetIds: Array<string>, seriesIds: Array<string>) {
    const ownerAdd = await owner.getAddress()

    const cauldron = (await deployContract(owner, CauldronArtifact, [])) as Cauldron
    const innerLadle = (await deployContract(owner, LadleArtifact, [cauldron.address])) as Ladle
    const ladle = new LadleWrapper(innerLadle)
    const witch = (await deployContract(owner, WitchArtifact, [cauldron.address, ladle.address])) as Witch

    // ==== Orchestration ====
    await this.cauldronLadleAuth(cauldron, ladle.address)
    await this.cauldronWitchAuth(cauldron, witch.address)
    await this.ladleWitchAuth(ladle, witch.address)

    // ==== Owner access (only test environment) ====
    await this.cauldronGovAuth(cauldron, ownerAdd)
    await this.cauldronLadleAuth(cauldron, ownerAdd)
    await this.ladleGovAuth(ladle, ownerAdd)
    await this.ladleWitchAuth(ladle, ownerAdd)

    // ==== Add assets and joins ====
    // For each asset id passed as an argument, we create a Mock ERC20 which we register in cauldron, and its Join, that we register in Ladle.
    // We also give 100 tokens of that asset to the owner account, and approve with the owner for the join to take the asset.
    const assets: Map<string, ERC20Mock> = new Map()
    const joins: Map<string, Join> = new Map()
    for (let assetId of assetIds) {
      const asset = await this.addAsset(owner, cauldron, assetId) as ERC20Mock
      assets.set(assetId, asset)

      const join = await this.addJoin(owner, ladle, asset, assetId) as Join
      joins.set(assetId, join)
      await join.grantRoles([
        id('join(address,uint128)'),
        id('exit(address,uint128)'),
        id('retrieve(address,address)')
      ], ownerAdd) // Only test environment
    }

    // The first asset will be the underlying for all series
    // All assets after the first will be added as collateral for all series
    const ilkIds = assetIds.slice(1)
    const baseId = assetIds[0]
    const base = assets.get(baseId) as ERC20Mock
    const baseJoin = joins.get(baseId) as Join

    // Add Ether as an asset, as well as WETH9 and the WETH9 Join
    const weth = (await deployContract(owner, WETH9MockArtifact, [])) as WETH9Mock
    await cauldron.addAsset(ETH, weth.address)

    const wethJoin = await this.addJoin(owner, ladle, weth as unknown as ERC20Mock, ETH) as Join
    await wethJoin.grantRoles([
      id('join(address,uint128)'),
      id('exit(address,uint128)'),
      id('retrieve(address,address)')
    ], ownerAdd) // Only test environment
    assets.set(ETH, weth as unknown as ERC20Mock)
    joins.set(ETH, wethJoin)
    ilkIds.push(ETH)

    // Add Dai as an asset
    const dai = (await deployContract(owner, DAIMockArtifact, [])) as DAIMock
    await cauldron.addAsset(DAI, dai.address)

    const daiJoin = await this.addJoin(owner, ladle, dai as unknown as ERC20Mock, DAI) as Join
    await daiJoin.grantRoles([
      id('join(address,uint128)'),
      id('exit(address,uint128)'),
      id('retrieve(address,address)')
    ], ownerAdd) // Only test environment
    assets.set(DAI, dai as unknown as ERC20Mock)
    joins.set(DAI, daiJoin)
    ilkIds.push(DAI)

    // Add USDC as an asset
    const usdc = (await deployContract(owner, USDCMockArtifact, [])) as USDCMock
    await cauldron.addAsset(USDC, usdc.address)

    const usdcJoin = await this.addJoin(owner, ladle, usdc as unknown as ERC20Mock, USDC) as Join
    await usdcJoin.grantRoles([
      id('join(address,uint128)'),
      id('exit(address,uint128)'),
      id('retrieve(address,address)')
    ], ownerAdd) // Only test environment
    assets.set(USDC, usdc as unknown as ERC20Mock)
    joins.set(USDC, usdcJoin)
    ilkIds.push(USDC)

    // ==== Set debt limits ====
    for (let ilkId of ilkIds) {
      await cauldron.setMaxDebt(baseId, ilkId, WAD.mul(1000000))
    }

    // ==== Add oracles ====
    const oracles: Map<string, OracleMock> = new Map()

    const rateOracle = await this.addRateOracle(owner, cauldron, baseId) as OracleMock
    oracles.set('rate', rateOracle)
    const chiOracle = await this.addChiOracle(owner) as OracleMock
    oracles.set('chi', chiOracle)
    
    // There is only one base, so the spot oracles we need are one for each ilk, against the only base.
    for (let ilkId of ilkIds) {
      oracles.set(ilkId, await this.addSpotOracle(owner, cauldron, baseId, ilkId) as OracleMock)
    }

    // ==== Add series and pools ====
    // For each series identifier we create a fyToken with the first asset as underlying.
    // The maturities for the fyTokens are in three month intervals, starting three months from now
    const series: Map<string, FYToken> = new Map()
    const pools: Map<string, PoolMock> = new Map()

    const provider: BaseProvider = await ethers.provider
    const now = (await provider.getBlock(await provider.getBlockNumber())).timestamp
    let count: number = 1
    for (let seriesId of seriesIds) {
      const maturity = now + THREE_MONTHS * count++
      const fyToken = await this.addSeries(owner, cauldron, ladle, baseJoin, chiOracle, seriesId, baseId, ilkIds, maturity) as FYToken
      series.set(seriesId, fyToken)
      await fyToken.grantRoles([id('mint(address,uint256)'), id('burn(address,uint256)')], ownerAdd) // Only test environment

      // Add a pool between the base and each series
      pools.set(seriesId, await this.addPool(owner, ladle, base, fyToken, seriesId))
    }

    // ==== Build some vaults ====
    // For each series and ilk we create a vault - vaults[seriesId][ilkId] = vaultId
    const vaults: Map<string, Map<string, string>> = new Map()
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

    return new YieldEnvironment(owner, cauldron, ladle, witch, assets, oracles, series, pools, joins, vaults)
  }
}
