import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { formatBytes32String as toBytes32, id } from 'ethers/lib/utils'
import { BigNumber, BigNumberish } from 'ethers'

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
  // joins: Map<string,Join>
  // fyTokens: Map<string,FYToken>
  // assets: Map<string,ERC20Mock>

  constructor(
    owner: SignerWithAddress,
    other: SignerWithAddress,
    vat: Vat,
    cdpProxy: CDPProxy,
    // assets: Map<string,ERC20Mock>,
    // fyTokens: Map<string,FYToken>,
    // joins: Map<string,Join>,
  ) {
    this.owner = owner
    this.other = other
    this.vat = vat
    this.cdpProxy = cdpProxy
    // this.assets = assets
    // this.fyTokens = fyTokens
    // this.joins = joins
  }

  public static async setup(owner: SignerWithAddress, other: SignerWithAddress/* assets: Array<string>, maturities: number */) {
    const ownerAdd = await owner.getAddress()
    const otherAdd = await other.getAddress()

    const vat = (await deployContract(owner, VatArtifact, [])) as Vat
    const cdpProxy = (await deployContract(owner, CDPProxyArtifact, [vat.address])) as CDPProxy

    // ==== Add assets, series and joins    
    // base = (await deployContract(ownerAcc, ERC20MockArtifact, [baseId, "Mock Base"])) as ERC20Mock
    // ilk = (await deployContract(ownerAcc, ERC20MockArtifact, [ilkId, "Mock Ilk"])) as ERC20Mock
    // fyToken = (await deployContract(ownerAcc, FYTokenArtifact, [base.address, mockAddress, maturity, seriesId, "Mock FYToken"])) as FYToken
    // join = (await deployContract(ownerAcc, JoinArtifact, [ilk.address])) as Join

    // ==== Build some vaults ====
    // await vat.build(seriesId, ilkId)
    // const event = (await vat.queryFilter(vat.filters.VaultBuilt(null, null, null, null)))[0]
    // vaultId = event.args.vaultId

    // ==== Give some assets
    // await ilk.mint(owner, 1);
    // await ilk.approve(join.address, MAX);

    return new YieldEnvironment(owner, other, vat, cdpProxy)
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