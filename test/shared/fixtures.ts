import { Wallet } from '@ethersproject/wallet'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { formatBytes32String as toBytes32, id } from 'ethers/lib/utils'
import { BigNumber, BigNumberish } from 'ethers'
import { BaseProvider } from '@ethersproject/providers'

import VatArtifact from '../../artifacts/contracts/Vat.sol/Vat.json'
import FYTokenArtifact from '../../artifacts/contracts/FYToken.sol/FYToken.json'
import ERC20MockArtifact from '../../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import OracleMockArtifact from '../../artifacts/contracts/mocks/OracleMock.sol/OracleMock.json'
import JoinArtifact from '../../artifacts/contracts/Join.sol/Join.json'
import CDPProxyArtifact from '../../artifacts/contracts/CDPProxy.sol/CDPProxy.json'

import { Vat } from '../../typechain/Vat'
import { FYToken } from '../../typechain/FYToken'
import { ERC20Mock } from '../../typechain/ERC20Mock'
import { OracleMock } from '../../typechain/OracleMock'
import { Join } from '../../typechain/Join'
import { CDPProxy } from '../../typechain/CDPProxy'

import { ethers, waffle } from 'hardhat'
// import { id } from '../src'
const { deployContract } = waffle

export const WAD = BigNumber.from("1000000000000000000")
export const RAY = BigNumber.from("1000000000000000000000000000")

export class YieldEnvironment {
  owner: SignerWithAddress
  vat: Vat
  cdpProxy: CDPProxy
  assets: Map<string, ERC20Mock>
  oracles: Map<string, OracleMock>
  series: Map<string, FYToken>
  joins: Map<string, Join>
  vaults: Map<string, Map<string, string>>
  
  constructor(
    owner: SignerWithAddress,
    vat: Vat,
    cdpProxy: CDPProxy,
    assets: Map<string, ERC20Mock>,
    oracles: Map<string, OracleMock>,
    series: Map<string, FYToken>,
    joins: Map<string, Join>,
    vaults: Map<string, Map<string, string>>
  ) {
    this.owner = owner
    this.vat = vat
    this.cdpProxy = cdpProxy
    this.assets = assets
    this.oracles = oracles
    this.series = series
    this.joins = joins
    this.vaults = vaults
  }

  // Set up a test environment. Provide at least one asset identifier.
  public static async setup(owner: SignerWithAddress, assetIds: Array<string>, seriesIds: Array<string>) {
    const ownerAdd = await owner.getAddress()

    const vat = (await deployContract(owner, VatArtifact, [])) as Vat
    const cdpProxy = (await deployContract(owner, CDPProxyArtifact, [vat.address])) as CDPProxy

    // ==== Add assets and joins ====
    // For each asset id passed as an argument, we create a Mock ERC20 which we register in vat, and its Join, that we register in CDPProxy.
    // We also give 100 tokens of that asset to the owner account, and approve with the owner for the join to take the asset.
    const assets: Map<string, ERC20Mock> = new Map()
    const joins: Map<string, Join> = new Map()
    for (let assetId of assetIds) {
      const asset = await deployContract(owner, ERC20MockArtifact, [assetId, "Mock Base"]) as ERC20Mock
      assets.set(assetId, asset)
      await vat.addAsset(assetId, asset.address)
      await asset.mint(ownerAdd, WAD.mul(100))

      const join = await deployContract(owner, JoinArtifact, [asset.address]) as Join
      joins.set(assetId, join)
      await cdpProxy.addJoin(assetId, join.address)
      await asset.approve(join.address, ethers.constants.MaxUint256)
    }

    // The first asset will be the underlying for all series
    // All assets after the first will be added as collateral for all series
    const baseId = assetIds[0]
    const ilkIds = assetIds.slice(1)
    const base = assets.get(baseId) as ERC20Mock

    // ==== Set debt limits ====
    for (let ilkId of ilkIds) {
      await vat.setMaxDebt(baseId, ilkId, WAD.mul(1000000))
    }

    // ==== Add oracles and series ====
    // There is only one base, so the oracles we need are one for each ilk, against the only base.
    const oracles: Map<string, OracleMock> = new Map()
    const ratio = 10000                                             //  10000 == 100% collateralization ratio
    for (let ilkId of ilkIds) {
      const oracle = (await deployContract(owner, OracleMockArtifact, [])) as OracleMock
      await oracle.setSpot(RAY.mul(2))
      await vat.addSpotOracle(baseId, ilkId, oracle.address, ratio) // This allows to set the ilks below.
      oracles.set(ilkId, oracle)
    }

    // For each series identifier we create a fyToken with the first asset as underlying.
    // The maturities for the fyTokens are in three month intervals, starting three months from now
    const series: Map<string, FYToken> = new Map()
    const mockOracleAddress =  ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20))) // This is a chi oracle
    const provider: BaseProvider = ethers.getDefaultProvider()
    const now = (await provider.getBlock(provider.getBlockNumber())).timestamp
    const THREE_MONTHS: number = 3 * 30 * 24 * 60 * 60
    let count: number = 1
    for (let seriesId of seriesIds) {
      const fyToken = (await deployContract(owner, FYTokenArtifact, [base.address, mockOracleAddress, now + THREE_MONTHS * count++, seriesId, "Mock FYToken"])) as FYToken
      series.set(seriesId, fyToken)
      await vat.addSeries(seriesId, baseId, fyToken.address)

      // Add all assets except the first one as approved collaterals
      for (let ilkId of assetIds.slice(1)) {
        await vat.addIlk(seriesId, ilkId)
      }
    }

    // ==== Build some vaults ====
    // For each series and ilk we create two vaults vaults[seriesId][ilkId] = vaultId
    const vaults: Map<string, Map<string, string>> = new Map()
    for (let seriesId of seriesIds) {
      const seriesVaults: Map<string, string> = new Map()
      for (let ilkId of ilkIds) {
        await vat.build(seriesId, ilkId)
        const event = (await vat.queryFilter(vat.filters.VaultBuilt(null, null, null, null)))[0]
        const vaultId = event.args.vaultId
        seriesVaults.set(ilkId, vaultId)
      }
      vaults.set(seriesId, seriesVaults)
    }

    return new YieldEnvironment(owner, vat, cdpProxy, assets, oracles, series, joins, vaults)
  }
}