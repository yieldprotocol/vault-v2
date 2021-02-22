import { Wallet } from '@ethersproject/wallet'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { formatBytes32String as toBytes32, id } from 'ethers/lib/utils'
import { BigNumber, BigNumberish } from 'ethers'
import { BaseProvider } from '@ethersproject/providers'

import VatArtifact from '../../artifacts/contracts/Vat.sol/Vat.json'
import JoinArtifact from '../../artifacts/contracts/Join.sol/Join.json'
import FYTokenArtifact from '../../artifacts/contracts/FYToken.sol/FYToken.json'
import ERC20MockArtifact from '../../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import CDPProxyArtifact from '../../artifacts/contracts/CDPProxy.sol/CDPProxy.json'

import { Vat } from '../../typechain/Vat'
import { Join } from '../../typechain/Join'
import { FYToken } from '../../typechain/FYToken'
import { ERC20Mock } from '../../typechain/ERC20Mock'
import { CDPProxy } from '../../typechain/CDPProxy'

/* import {
  WETH,
  CHAI,
  Line,
  spotName,
  linel,
  limits,
  spot,
  rate1,
  chi1,
  tag,
  fix,
  toRay,
  subBN,
  divRay,
  divrupRay,
  mulRay,
} from './utils' */

import { ethers, waffle } from 'hardhat'
// import { id } from '../src'
import { expect } from 'chai'
const { deployContract } = waffle

export class YieldEnvironment {
  owner: SignerWithAddress
  other: SignerWithAddress
  vat: Vat
  cdpProxy: CDPProxy
  joins: Map<string, Join>
  assets: Map<string, ERC20Mock>
  series: Map<string, FYToken>
  vaults: Map<string, Map<string, string>>
  
  constructor(
    owner: SignerWithAddress,
    other: SignerWithAddress,
    vat: Vat,
    cdpProxy: CDPProxy,
    assets: Map<string, ERC20Mock>,
    joins: Map<string, Join>,
    series: Map<string, FYToken>,
    vaults: Map<string, Map<string, string>>
  ) {
    this.owner = owner
    this.other = other
    this.vat = vat
    this.cdpProxy = cdpProxy
    this.assets = assets
    this.joins = joins
    this.series = series
    this.vaults = vaults
  }

  // Set up a test environment. Provide at least one asset identifier.
  public static async setup(owner: SignerWithAddress, other: SignerWithAddress, assetIds: Array<string>, seriesIds: Array<string>) {
    const ownerAdd = await owner.getAddress()
    const otherAdd = await other.getAddress()

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
      await asset.mint(ownerAdd, ethers.constants.WeiPerEther.mul(100))

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
      await vat.setMaxDebt(baseId, ilkId, ethers.constants.MaxUint256)
    }

    // ==== Add series ====
    // For each series identifier we create a fyToken with the first asset as underlying.
    // The maturities for the fyTokens are in three month intervals, starting three months from now
    const series: Map<string, FYToken> = new Map()
    const mockOracleAddress =  ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))
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

    return new YieldEnvironment(owner, other, vat, cdpProxy, assets, joins, series, vaults)
  }

  /*
  public async getDai(user: string, _daiTokens: BigNumberish, _rate: BigNumberish) {
    await this.vat.hope(this.daiJoin.address, { from: user })
    await this.vat.hope(this.wethJoin.address, { from: user })

    const _daiDebt = divrupRay(_daiTokens, _rate).add(2).toString() // For very low values of rate, we can lose up to two wei dai debt, reverting the exit below
    const _wethTokens = divRay(_daiTokens, spot).mul(2).toString() // We post twice the amount of weth needed to remain collateralized after future rate increases

    await this.weth.deposit({ from: user, value: _wethTokens })
    await this.weth.approve(this.wethJoin.address, _wethTokens, { from: user })
    await this.wethJoin.join(user, _wethTokens, { from: user })
    await this.vat.frob(WETH, user, user, user, _wethTokens, _daiDebt, { from: user })
    await this.daiJoin.exit(user, _daiTokens, { from: user })
  }

  // With rounding somewhere, this might get one less chai wei than expected
  public async getChai(user: string, _chaiTokens: BigNumberish, _chi: BigNumberish, _rate: BigNumberish) {
    const _daiTokens = mulRay(_chaiTokens, _chi).add(1)
    await this.getDai(user, _daiTokens, _rate)
    await this.dai.approve(this.chai.address, _daiTokens, { from: user })
    await this.chai.join(user, _daiTokens, { from: user })
  }
  */

  /* public static async setupFYDais(treasury: Contract, maturities: Array<number>): Promise<Array<Contract>> {
    return await Promise.all(
      maturities.map(async (maturity) => {
        const fyDai = await FYDai.new(treasury.address, maturity, 'Name', 'Symbol')
        await treasury.orchestrate(fyDai.address, id('pullDai(address,uint256)'))
        return fyDai
      })
    )
  } */

  /* public static async setup(maturities: Array<number>) {
    const maker = await MakerEnvironment.setup()
    const treasury = await this.setupTreasury(maker)
    const fyDais = await this.setupFYDais(treasury, maturities)
    const controller = await this.setupController(treasury, fyDais)
    return new YieldEnvironmentLite(maker, treasury, controller, fyDais)
  } */
}