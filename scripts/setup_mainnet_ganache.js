const Migrations = artifacts.require('Migrations')
const Chai = artifacts.require('Chai')
const Controller = artifacts.require('Controller')
const Dai = artifacts.require('Dai')
const DaiJoin = artifacts.require('DaiJoin')
const FYDai = artifacts.require('FYDai')
const Treasury = artifacts.require('Treasury')
const Vat = artifacts.require('Vat')
const WETH9 = artifacts.require('WETH9')
const GemJoin = artifacts.require('GemJoin')
const Pool = artifacts.require('Pool')
const Pot = artifacts.require('Pot')
const YieldProxy = artifacts.require('YieldProxy')

const ethers = require('ethers')

// Logs all addresses of contracts
module.exports = async (callback) => {
  try {
    migrations = await Migrations.deployed()

    chai = await Chai.at(await migrations.contracts(ethers.utils.formatBytes32String('Chai')))
    controller = await Controller.at(await migrations.contracts(ethers.utils.formatBytes32String('Controller')))
    dai = await Dai.at(await migrations.contracts(ethers.utils.formatBytes32String('Dai')))
    daiJoin = await DaiJoin.at(await migrations.contracts(ethers.utils.formatBytes32String('DaiJoin')))
    fyDai0 = await FYDai.at(await migrations.contracts(ethers.utils.formatBytes32String('fyDai20Sep')))
    fyDai1 = await FYDai.at(await migrations.contracts(ethers.utils.formatBytes32String('fyDai20Oct')))
    fyDai2 = await FYDai.at(await migrations.contracts(ethers.utils.formatBytes32String('fyDai21Jan')))
    fyDai3 = await FYDai.at(await migrations.contracts(ethers.utils.formatBytes32String('fyDai21Apr')))
    fyDai4 = await FYDai.at(await migrations.contracts(ethers.utils.formatBytes32String('fyDai21Jul')))
    treasury = await Treasury.at(await migrations.contracts(ethers.utils.formatBytes32String('Treasury')))
    vat = await Vat.at(await migrations.contracts(ethers.utils.formatBytes32String('Vat')))
    weth = await WETH9.at(await migrations.contracts(ethers.utils.formatBytes32String('Weth')))
    wethJoin = await GemJoin.at(await migrations.contracts(ethers.utils.formatBytes32String('WethJoin')))
    pool0 = await Pool.at(await migrations.contracts(ethers.utils.formatBytes32String('fyDaiLP20Sep')))
    pool1 = await Pool.at(await migrations.contracts(ethers.utils.formatBytes32String('fyDaiLP20Oct')))
    pool2 = await Pool.at(await migrations.contracts(ethers.utils.formatBytes32String('fyDaiLP21Jan')))
    pool3 = await Pool.at(await migrations.contracts(ethers.utils.formatBytes32String('fyDaiLP21Apr')))
    pool4 = await Pool.at(await migrations.contracts(ethers.utils.formatBytes32String('fyDaiLP21Jul')))
    pot = await Pot.at(await migrations.contracts(ethers.utils.formatBytes32String('Pot')))
    yieldProxy = await YieldProxy.at(await migrations.contracts(ethers.utils.formatBytes32String('YieldProxy')))
    console.log('Contracts loaded')

    me = (await web3.eth.getAccounts())[0]

    WAD = '000000000000000000'
    THOUSAND = '000'
    MILLION = '000000'

    MAX = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    Line = web3.utils.fromAscii('Line')
    line = web3.utils.fromAscii('line')
    spot = web3.utils.fromAscii('spot')
    ETH_A = web3.utils.fromAscii('ETH-A')

    maturity0 = await fyDai0.maturity()
    maturity1 = await fyDai1.maturity()
    maturity2 = await fyDai2.maturity()
    maturity3 = await fyDai3.maturity()
    maturity4 = await fyDai4.maturity()

    await vat.hope(daiJoin.address)
    await weth.approve(treasury.address, MAX)
    await weth.approve(wethJoin.address, MAX)
    await dai.approve(pool0.address, MAX)
    await dai.approve(pool1.address, MAX)
    await dai.approve(pool2.address, MAX)
    await dai.approve(pool3.address, MAX)
    await dai.approve(pool4.address, MAX)
    await dai.approve(yieldProxy.address, MAX)
    await fyDai0.approve(pool0.address, MAX)
    await fyDai1.approve(pool1.address, MAX)
    await fyDai2.approve(pool2.address, MAX)
    await fyDai3.approve(pool3.address, MAX)
    await fyDai4.approve(pool4.address, MAX)
    console.log('Approvals granted')

    if (!(await controller.delegated(me, yieldProxy.address))) {
      await controller.addDelegate(yieldProxy.address)
      await pool0.addDelegate(yieldProxy.address)
      await pool1.addDelegate(yieldProxy.address)
      await pool2.addDelegate(yieldProxy.address)
      await pool3.addDelegate(yieldProxy.address)
      await pool4.addDelegate(yieldProxy.address)
      console.log('Delegates granted')
    }

    await weth.deposit({ value: '70' + THOUSAND + WAD })
    console.log('Weth obtained')

    await wethJoin.join(me, '10' + THOUSAND + WAD)
    await vat.frob(ETH_A, me, me, me, '10' + THOUSAND + WAD, '2' + MILLION + WAD)
    await daiJoin.exit(me, '2' + MILLION + WAD)
    console.log('Dai obtained')

    await controller.post(ETH_A, me, me, '50' + THOUSAND + WAD)

    await controller.borrow(ETH_A, maturity0, me, me, '100' + THOUSAND + WAD)
    await controller.borrow(ETH_A, maturity1, me, me, '100' + THOUSAND + WAD)
    await controller.borrow(ETH_A, maturity2, me, me, '100' + THOUSAND + WAD)
    await controller.borrow(ETH_A, maturity3, me, me, '100' + THOUSAND + WAD)
    await controller.borrow(ETH_A, maturity4, me, me, '100' + THOUSAND + WAD)
    console.log('fyDai obtained')

    await pool0.mint(me, me, '100' + THOUSAND + WAD)
    await pool1.mint(me, me, '100' + THOUSAND + WAD)
    await pool2.mint(me, me, '100' + THOUSAND + WAD)
    await pool3.mint(me, me, '100' + THOUSAND + WAD)
    await pool4.mint(me, me, '100' + THOUSAND + WAD)
    console.log('Pools initialized')

    await yieldProxy.addLiquidity(pool0.address, '100' + THOUSAND + WAD, MAX)
    await yieldProxy.addLiquidity(pool1.address, '100' + THOUSAND + WAD, MAX)
    await yieldProxy.addLiquidity(pool2.address, '100' + THOUSAND + WAD, MAX)
    await yieldProxy.addLiquidity(pool3.address, '100' + THOUSAND + WAD, MAX)
    await yieldProxy.addLiquidity(pool4.address, '100' + THOUSAND + WAD, MAX)
    console.log('Liquidity added')

    await yieldProxy.sellFYDai(pool0.address, me, '25' + THOUSAND + WAD, 0)
    await yieldProxy.sellFYDai(pool1.address, me, '25' + THOUSAND + WAD, 0)
    await yieldProxy.sellFYDai(pool2.address, me, '25' + THOUSAND + WAD, 0)
    await yieldProxy.sellFYDai(pool3.address, me, '25' + THOUSAND + WAD, 0)
    await yieldProxy.sellFYDai(pool4.address, me, '25' + THOUSAND + WAD, 0)
    console.log('fyDai sold')

    callback()
  } catch (e) {
    console.log(e)
  }
}
