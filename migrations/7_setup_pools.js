const ethers = require('ethers')
const BigNumber = ethers.BigNumber

const toWad = (value) => {
  let exponent = BigNumber.from(10).pow(BigNumber.from(8))
  return BigNumber.from((value) * 10 ** 10).mul(exponent)
}

const toRay = (value) => {
  let exponent = BigNumber.from(10).pow(BigNumber.from(17))
  return BigNumber.from(Math.floor((value) * 10 ** 10)).mul(exponent)
}

const divrupRay = (x, ray) => {
  const RAY = BigNumber.from(10).pow(BigNumber.from(27))
  const z = RAY.mul(x).div(ray)
  if (z.mul(ray).div(RAY) < x) return z.add(BigNumber.from(1))
  return z
}

const Migrations = artifacts.require('Migrations')

const Vat = artifacts.require('Vat')
const Weth = artifacts.require('WETH9')
const Dai = artifacts.require('Dai')
const GemJoin = artifacts.require('GemJoin')
const DaiJoin = artifacts.require('DaiJoin')
const EDai = artifacts.require('EDai')
const Treasury = artifacts.require('Treasury')
const Controller = artifacts.require('Controller')
const Pool = artifacts.require('Pool')

const daiReserves = toWad(1000) // Increase to 10000 for Kovan
const targetRate = 1.05
const YEAR = 60*60*24*365
const ETH_A = web3.utils.fromAscii("ETH-A")
const MAX = "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

module.exports = async (deployer, network) => {

  if (network === 'mainnet') return

  const migrations = await Migrations.deployed()
  const vat = await Vat.deployed()
  const weth = await Weth.deployed()
  const wethJoin = await GemJoin.deployed()
  const dai = await Dai.deployed()
  const daiJoin = await DaiJoin.deployed()
  const treasury = await Treasury.deployed()
  const controller = await Controller.deployed()

  const me = (await web3.eth.getAccounts())[0]

  const eDaiToSell = (maturity, rate, daiReserves) => {
    const fromDate = Math.round((new Date()).getTime() / 1000)
    const secsToMaturity = maturity - fromDate
    const propOfYear = secsToMaturity/YEAR
    const price = 1 / Math.pow(rate, propOfYear)
    const priceRay = toRay(price)
    return divrupRay(daiReserves, priceRay).sub(daiReserves)
  };

  const pools = {}
  let totalEDai = BigNumber.from(0)
  let totalDai = BigNumber.from(0)
  for (let i = 0; i < (await migrations.length()); i++) {
    const contractName = web3.utils.toAscii(await migrations.names(i))
    if (!contractName.includes('eDaiLP')) continue
    const _pool = await Pool.at(await migrations.contracts(web3.utils.fromAscii(contractName)))
    const _eDai = await EDai.at(await _pool.eDai())
    const _maturity = await _eDai.maturity()
    const _eDaiToSell = eDaiToSell(_maturity, targetRate, daiReserves)
    totalEDai = totalEDai.add(_eDaiToSell)
    totalDai = totalDai.add(daiReserves)

    pools[contractName] = { 
      pool: _pool,
      eDai: _eDai,
      maturity: _maturity,
      eDaiToSell: _eDaiToSell,
    }
  }
  console.log()
  console.log(`   > Total Dai required: ${ totalDai.toString() }`)
  console.log(`   > Total EDai required: ${ totalEDai.toString() }`)

  const rate = BigNumber.from((await vat.ilks(ETH_A)).rate.toString()) // I could also use BN throughout
  const spot = BigNumber.from((await vat.ilks(ETH_A)).spot.toString())
  const normalizedDai = divrupRay(totalDai, rate).add(BigNumber.from('1')) // Rounding up
  const wethForDai = divrupRay(totalDai, spot).add(BigNumber.from('1')) // Rounding up
  const wethForEDai = divrupRay(totalEDai, spot).add(BigNumber.from('1')) // Rounding up

  // Initialize pools
  await weth.deposit({ value: wethForDai.add(wethForEDai).toString() })
  console.log(`   > Obtained ${(await weth.balanceOf(me)).toString()} weth`)

  // Get Dai
  await weth.approve(wethJoin.address, MAX)  
  await wethJoin.join(me, wethForDai)
  await vat.frob(ETH_A, me, me, me, wethForDai, normalizedDai)
  await vat.hope(daiJoin.address)
  await daiJoin.exit(me, totalDai)
  console.log(`   > Converted ${wethForDai.toString()} weth into ${(await dai.balanceOf(me)).toString()} dai`)

  // Post collateral for borrowing EDai
  await weth.approve(treasury.address, MAX)
  await controller.post(ETH_A, me, me, wethForEDai)
  console.log(`   > Posted ${wethForEDai.toString()} weth into the Controller`)

  // Init pools and sell EDai
  for (let name in pools) {
    const pool = pools[name].pool
    const eDai = pools[name].eDai
    const maturity = pools[name].maturity
    const eDaiToSell = pools[name].eDaiToSell

    console.log()
    console.log(`   ${name}`)
    console.log('   -----------')

    await dai.approve(pool.address, MAX)
    await pool.init(daiReserves)
    console.log(`   > Initialized ${name} with ${(await pool.getDaiReserves()).toString()} dai`)

    await controller.borrow(ETH_A, maturity, me, me, eDaiToSell)
    console.log(`   > Borrowed ${(await controller.debtEDai(ETH_A, maturity, me)).toString()} ${await eDai.name()} EDai`)
    await eDai.approve(pool.address, MAX)
    await pool.sellEDai(me, me, eDaiToSell)
    console.log(`   > Sold ${eDaiToSell.toString()} ${await eDai.name()} EDai`)

    // Consider joining the Dai to vat, and recovering the ETH
  }
}