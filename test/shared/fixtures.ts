import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { BaseProvider } from '@ethersproject/providers'
import { id } from '@yield-protocol/utils'
import { WAD, RAY, THREE_MONTHS } from './constants'

import CauldronArtifact from '../../artifacts/contracts/Cauldron.sol/Cauldron.json'
import FYTokenArtifact from '../../artifacts/contracts/FYToken.sol/FYToken.json'
import ERC20MockArtifact from '../../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import WETH9MockArtifact from '../../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import PoolMockArtifact from '../../artifacts/contracts/mocks/PoolMock.sol/PoolMock.json'
import OracleMockArtifact from '../../artifacts/contracts/mocks/OracleMock.sol/OracleMock.json'
import JoinArtifact from '../../artifacts/contracts/Join.sol/Join.json'
import LadleArtifact from '../../artifacts/contracts/Ladle.sol/Ladle.json'
import WitchArtifact from '../../artifacts/contracts/Witch.sol/Witch.json'

import { Cauldron } from '../../typechain/Cauldron'
import { FYToken } from '../../typechain/FYToken'
import { ERC20Mock } from '../../typechain/ERC20Mock'
import { WETH9Mock } from '../../typechain/WETH9Mock'
import { PoolMock } from '../../typechain/PoolMock'
import { OracleMock } from '../../typechain/OracleMock'
import { Join } from '../../typechain/Join'
import { Ladle } from '../../typechain/Ladle'
import { Witch } from '../../typechain/Witch'

import { ethers, waffle } from 'hardhat'
const { deployContract } = waffle

export class YieldEnvironment {
  owner: SignerWithAddress
  cauldron: Cauldron
  ladle: Ladle
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
    ladle: Ladle,
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

  public static async cauldronGovAuth(owner: SignerWithAddress, cauldron: Cauldron, receiver: string) {
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

  public static async cauldronLadleAuth(owner: SignerWithAddress, cauldron: Cauldron, receiver: string) {
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

  public static async cauldronWitchAuth(owner: SignerWithAddress, cauldron: Cauldron, receiver: string) {
    await cauldron.grantRoles(
      [
        id('destroy(bytes12)'),
        id('grab(bytes12)'),
      ],
      receiver
    )
  }

  public static async ladleGovAuth(owner: SignerWithAddress, ladle: Ladle, receiver: string) {
    await ladle.grantRoles(
      [
        id('addJoin(bytes6,address)'),
        id('addPool(bytes6,address)'),
      ],
      receiver
    )
  }

  public static async ladleWitchAuth(owner: SignerWithAddress, ladle: Ladle, receiver: string) {
    await ladle.grantRoles([
      id(
        'settle(bytes12,address,uint128,uint128)'
      )],
      receiver
    )
  }

  public static async addAsset(owner: SignerWithAddress, cauldron: Cauldron, assetId: string) {
    const asset = (await deployContract(owner, ERC20MockArtifact, [assetId, 'Mock Base'])) as ERC20Mock
    await cauldron.addAsset(assetId, asset.address)
    await asset.mint(await owner.getAddress(), WAD.mul(100))
    return asset
  }

  public static async addJoin(owner: SignerWithAddress, ladle: Ladle, asset: ERC20Mock, assetId: string) {
    const join = (await deployContract(owner, JoinArtifact, [asset.address])) as Join
    await ladle.addJoin(assetId, join.address)
    await asset.approve(join.address, ethers.constants.MaxUint256) // Owner approves all joins to take from him. Only testing
    await join.grantRoles([id('join(address,uint128)'), id('exit(address,uint128)')], ladle.address)
    return join
  }

  // Set up a test environment. Provide at least one asset identifier.
  public static async setup(owner: SignerWithAddress, assetIds: Array<string>, seriesIds: Array<string>) {
    const ownerAdd = await owner.getAddress()

    const cauldron = (await deployContract(owner, CauldronArtifact, [])) as Cauldron
    const ladle = (await deployContract(owner, LadleArtifact, [cauldron.address])) as Ladle
    const witch = (await deployContract(owner, WitchArtifact, [cauldron.address, ladle.address])) as Witch

    // ==== Orchestration ====
    await this.cauldronLadleAuth(owner, cauldron, ladle.address)
    await this.cauldronWitchAuth(owner, cauldron, witch.address)
    await this.ladleWitchAuth(owner, ladle, witch.address)

    // ==== Owner access (only test environment) ====
    await this.cauldronGovAuth(owner, cauldron, ownerAdd)
    await this.cauldronLadleAuth(owner, cauldron, ownerAdd)
    await this.ladleGovAuth(owner, ladle, ownerAdd)
    await this.ladleWitchAuth(owner, ladle, ownerAdd)

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
      await join.grantRoles([id('join(address,uint128)'), id('exit(address,uint128)')], ownerAdd) // Only test environment
    }

    // The first asset will be the underlying for all series
    // All assets after the first will be added as collateral for all series
    const baseId = assetIds[0]
    const ilkIds = assetIds.slice(1)
    const base = assets.get(baseId) as ERC20Mock

    // Add Ether as an asset

    // Deploy WETH9 and the WETH9 Join
    const ethId = ethers.utils.formatBytes32String('ETH').slice(0, 14)
    const weth = (await deployContract(owner, WETH9MockArtifact, [])) as WETH9Mock
    await cauldron.addAsset(ethId, weth.address)

    const join = await this.addJoin(owner, ladle, weth as unknown as ERC20Mock, ethId) as Join
    joins.set(ethId, join)
    ilkIds.push(ethId)

    // ==== Set debt limits ====
    for (let ilkId of ilkIds) {
      await cauldron.setMaxDebt(baseId, ilkId, WAD.mul(1000000))
    }

    // ==== Add oracles and series ====
    // There is only one base, so the oracles we need are one for each ilk, against the only base.
    const oracles: Map<string, OracleMock> = new Map()
    const oracle = (await deployContract(owner, OracleMockArtifact, [])) as OracleMock
    await oracle.setSpot(RAY.mul(2))
    await cauldron.setRateOracle(baseId, oracle.address) // This allows to set the series below.
    oracles.set('rate', oracle)

    const ratio = 10000 //  10000 == 100% collateralization ratio
    for (let ilkId of ilkIds) {
      const oracle = (await deployContract(owner, OracleMockArtifact, [])) as OracleMock
      await oracle.setSpot(RAY.mul(2))
      await cauldron.setSpotOracle(baseId, ilkId, oracle.address, ratio) // This allows to set the ilks below.
      oracles.set(ilkId, oracle)
    }

    // For each series identifier we create a fyToken with the first asset as underlying.
    // The maturities for the fyTokens are in three month intervals, starting three months from now
    const series: Map<string, FYToken> = new Map()
    const pools: Map<string, PoolMock> = new Map()
    const chiOracle = (await deployContract(owner, OracleMockArtifact, [])) as OracleMock // Not storing this one in `oracles`, you can retrieve it from the fyToken
    await chiOracle.setSpot(RAY)
    oracles.set('chi', chiOracle)
    const provider: BaseProvider = await ethers.provider
    const now = (await provider.getBlock(await provider.getBlockNumber())).timestamp
    let count: number = 1
    const baseJoin = joins.get(baseId) as Join
    for (let seriesId of seriesIds) {
      const fyToken = (await deployContract(owner, FYTokenArtifact, [
        chiOracle.address,
        baseJoin.address,
        now + THREE_MONTHS * count++,
        seriesId,
        'Mock FYToken',
      ])) as FYToken
      series.set(seriesId, fyToken)
      await cauldron.addSeries(seriesId, baseId, fyToken.address)

      // Add all ilks to each series
      await cauldron.addIlks(seriesId, ilkIds)

      await baseJoin.grantRoles([id('join(address,uint128)'), id('exit(address,uint128)')], fyToken.address)
      await fyToken.grantRoles([id('mint(address,uint256)'), id('burn(address,uint256)')], ladle.address)
      await fyToken.grantRoles([id('mint(address,uint256)'), id('burn(address,uint256)')], ownerAdd)

      // Add a pool between the base and each series
      const pool = (await deployContract(owner, PoolMockArtifact, [
        base.address,
        fyToken.address,
      ])) as PoolMock
      pools.set(seriesId, pool)
      await ladle.addPool(seriesId, pool.address)

      // Initialize pool with a million tokens of each
      await fyToken.mint(pool.address, WAD.mul(1000000))
      await base.mint(pool.address, WAD.mul(1000000))
      await pool.sync()
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
