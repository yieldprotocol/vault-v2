import { formatBytes32String as toBytes32, id } from 'ethers/lib/utils'
import { BigNumber, BigNumberish } from 'ethers'

export type Contract = any

const Vat = artifacts.require('Vat')
const GemJoin = artifacts.require('GemJoin')
const DaiJoin = artifacts.require('DaiJoin')
const Weth = artifacts.require('WETH9')
const ERC20 = artifacts.require('TestERC20')
const Dai = artifacts.require('TestDai')
const Pot = artifacts.require('Pot')
const End = artifacts.require('End')
const Chai = artifacts.require('Chai')
const Treasury = artifacts.require('Treasury')
const YDai = artifacts.require('YDai')
const Controller = artifacts.require('Controller')
const Liquidations = artifacts.require('Liquidations')
const Unwind = artifacts.require('Unwind')

import {
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
} from './utils'

export class MakerEnvironment {
  vat: Contract
  weth: Contract
  wethJoin: Contract
  dai: Contract
  daiJoin: Contract
  chai: Contract
  pot: Contract
  end: Contract

  constructor(
    vat: Contract,
    weth: Contract,
    wethJoin: Contract,
    dai: Contract,
    daiJoin: Contract,
    chai: Contract,
    pot: Contract,
    end: Contract
  ) {
    this.vat = vat
    this.weth = weth
    this.wethJoin = wethJoin
    this.dai = dai
    this.daiJoin = daiJoin
    this.chai = chai
    this.pot = pot
    this.end = end
  }

  public static async setup() {
    // Set up vat, join and weth
    const vat = await Vat.new()
    await vat.init(WETH) // Set WETH rate to 1.0

    const weth = await Weth.new()
    const wethJoin = await GemJoin.new(vat.address, WETH, weth.address)

    const dai = await Dai.new(0)
    const daiJoin = await DaiJoin.new(vat.address, dai.address)

    // Setup vat
    await vat.file(WETH, spotName, spot)
    await vat.file(WETH, linel, limits)
    await vat.file(Line, limits)
    await vat.fold(WETH, vat.address, subBN(rate1, toRay(1))) // Fold only the increase from 1.0

    // Setup pot
    const pot = await Pot.new(vat.address)
    await pot.setChi(chi1)

    // Setup chai
    const chai = await Chai.new(vat.address, pot.address, daiJoin.address, dai.address)

    // Setup end
    const end = await End.new()
    await end.file(toBytes32('vat'), vat.address)

    // Permissions
    await vat.rely(vat.address)
    await vat.rely(wethJoin.address)
    await vat.rely(daiJoin.address)
    await vat.rely(pot.address)
    await vat.rely(end.address)

    return new MakerEnvironment(vat, weth, wethJoin, dai, daiJoin, chai, pot, end)
  }

  public async getDai(user: string, _daiTokens: BigNumberish, _rate: BigNumberish) {
    await this.vat.hope(this.daiJoin.address, { from: user })
    await this.vat.hope(this.wethJoin.address, { from: user })

    const _daiDebt = divrupRay(_daiTokens, _rate).toString()
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
}

export class YieldEnvironmentLite {
  maker: MakerEnvironment
  treasury: Contract
  controller: Contract
  yDais: Array<Contract>

  constructor(maker: MakerEnvironment, treasury: Contract, controller: Contract, yDais: Array<Contract>) {
    this.maker = maker
    this.treasury = treasury
    this.controller = controller
    this.yDais = yDais
  }

  public static async setupTreasury(maker: MakerEnvironment) {
    return Treasury.new(
      maker.vat.address,
      maker.weth.address,
      maker.dai.address,
      maker.wethJoin.address,
      maker.daiJoin.address,
      maker.pot.address,
      maker.chai.address
    )
  }

  public static async setupController(treasury: Contract, yDais: Array<Contract>) {
    const yDaiAddrs = yDais.map((c) => c.address)
    const controller = await Controller.new(treasury.address, yDaiAddrs)
    const treasuryFunctions = ['pushDai', 'pullDai', 'pushChai', 'pullChai', 'pushWeth', 'pullWeth'].map((func) =>
      id(func + '(address,uint256)')
    )
    await treasury.batchOrchestrate(controller.address, treasuryFunctions)

    for (const yDai of yDais) {
      await yDai.batchOrchestrate(controller.address, [id('mint(address,uint256)'), id('burn(address,uint256)')])
    }

    return controller
  }

  public static async setupYDais(treasury: Contract, maturities: Array<number>): Promise<Array<Contract>> {
    return await Promise.all(
      maturities.map(async (maturity) => {
        const yDai = await YDai.new(treasury.address, maturity, 'Name', 'Symbol')
        await treasury.orchestrate(yDai.address, id('pullDai(address,uint256)'))
        return yDai
      })
    )
  }

  public static async setup(maturities: Array<number>) {
    const maker = await MakerEnvironment.setup()
    const treasury = await this.setupTreasury(maker)
    const yDais = await this.setupYDais(treasury, maturities)
    const controller = await this.setupController(treasury, yDais)
    return new YieldEnvironmentLite(maker, treasury, controller, yDais)
  }

  public async newYDai(maturity: number, name: string, symbol: string) {
    const yDai = await YDai.new(this.treasury.address, maturity, name, symbol)
    await this.treasury.orchestrate(yDai.address, id('pullDai(address,uint256)'))
    return yDai
  }

  // Convert eth to weth and post it to yDai
  public async postWeth(user: string, _wethTokens: BigNumberish) {
    await this.maker.weth.deposit({ from: user, value: _wethTokens.toString() })
    await this.maker.weth.approve(this.treasury.address, _wethTokens, { from: user })
    await this.controller.post(WETH, user, user, _wethTokens, { from: user })
  }

  // Convert eth to chai and post it to yDai
  public async postChai(user: string, _chaiTokens: BigNumberish, _chi: BigNumberish, _rate: BigNumberish) {
    await this.maker.getChai(user, _chaiTokens, _chi, _rate)
    await this.maker.chai.approve(this.treasury.address, _chaiTokens, { from: user })
    await this.controller.post(CHAI, user, user, _chaiTokens, { from: user })
  }
}

export class YieldEnvironment extends YieldEnvironmentLite {
  liquidations: Contract
  unwind: Contract

  constructor(
    maker: MakerEnvironment,
    treasury: Contract,
    controller: Contract,
    yDais: Contract,
    liquidations: Contract,
    unwind: Contract
  ) {
    super(maker, treasury, controller, yDais)
    this.liquidations = liquidations
    this.unwind = unwind
  }

  public static async setup(maturities: Array<number>) {
    const { maker, treasury, controller, yDais } = await YieldEnvironmentLite.setup(maturities)

    const liquidations = await Liquidations.new(controller.address)
    await controller.orchestrate(liquidations.address, id('erase(bytes32,address)'))
    await treasury.batchOrchestrate(liquidations.address, [
      id('pushDai(address,uint256)'),
      id('pullWeth(address,uint256)'),
    ])

    const unwind = await Unwind.new(maker.end.address, liquidations.address)
    await treasury.registerUnwind(unwind.address)
    await controller.orchestrate(unwind.address, id('erase(bytes32,address)'))
    await liquidations.orchestrate(unwind.address, id('erase(address)'))

    for (const ydai of yDais) {
      await ydai.orchestrate(unwind.address, id('burn(address,uint256)'))
    }

    return new YieldEnvironment(maker, treasury, controller, yDais, liquidations, unwind)
  }

  public async shutdown(owner: string, user1: string, user2: string) {
    await this.maker.end.cage()
    await this.maker.end.setTag(WETH, tag)
    await this.maker.end.setDebt(1)
    await this.maker.end.setFix(WETH, fix)
    await this.maker.end.skim(WETH, user1)
    await this.maker.end.skim(WETH, user2)
    await this.maker.end.skim(WETH, owner)
    await this.unwind.unwind()
    await this.unwind.settleTreasury()
    await this.unwind.cashSavings()
  }
}
