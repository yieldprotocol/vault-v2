const ethers = require('ethers')
const BigNumber = ethers.BigNumber

const toWad = (value) => {
  let exponent = BigNumber.from(10).pow(BigNumber.from(8))
  return BigNumber.from(Math.round((value) * 10 ** 10)).mul(exponent)
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
const FYDai = artifacts.require('FYDai')
const Treasury = artifacts.require('Treasury')
const Controller = artifacts.require('Controller')
const Pool = artifacts.require('Pool')

const daiReserves = toWad(1000) // Tailor to each deployment.
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


  const pools = {}
  let totalFYDai = BigNumber.from(0)
  let totalDai = BigNumber.from(0)
  for (let i = 0; i < (await migrations.length()); i++) {
    const contractName = web3.utils.toAscii(await migrations.names(i))
    if (!contractName.includes('fyDaiLP')) continue
    const _pool = await Pool.at(await migrations.contracts(web3.utils.fromAscii(contractName)))
    const _fyDai = await FYDai.at(await _pool.fyDai())
    const _maturity = await _fyDai.maturity()
    // const _fyDaiToSell = fyDaiToSell(_maturity, targetRate, daiReserves)
    const _fyDaiToSell = daiReserves.div(BigNumber.from(9)) // fyDaiToSell(_maturity, targetRate, daiReserves)
    totalFYDai = totalFYDai.add(_fyDaiToSell)
    totalDai = totalDai.add(daiReserves)

    pools[contractName] = { 
      pool: _pool,
      fyDai: _fyDai,
      maturity: _maturity,
      fyDaiToSell: _fyDaiToSell,
    }
  }
  console.log()
  console.log(`   > Total Dai required: ${ totalDai.toString() }`)
  console.log(`   > Total FYDai required: ${ totalFYDai.toString() }`)

  const rate = BigNumber.from((await vat.ilks(ETH_A)).rate.toString()) // I could also use BN throughout
  const spot = BigNumber.from((await vat.ilks(ETH_A)).spot.toString())
  const normalizedDai = divrupRay(totalDai, rate).add(BigNumber.from('1')) // Rounding up
  const wethForDai = divrupRay(totalDai, spot).add(BigNumber.from('1')) // Rounding up
  const wethForFYDai = divrupRay(totalFYDai, spot).add(BigNumber.from('1')) // Rounding up

  // Initialize pools
  await weth.deposit({ value: wethForDai.add(wethForFYDai).toString() })
  console.log(`   > Obtained ${(await weth.balanceOf(me)).toString()} weth`)

  // Get Dai
  await weth.approve(wethJoin.address, MAX)  
  await wethJoin.join(me, wethForDai)
  await vat.frob(ETH_A, me, me, me, wethForDai, normalizedDai)
  await vat.hope(daiJoin.address)
  await daiJoin.exit(me, totalDai)
  console.log(`   > Converted ${wethForDai.toString()} weth into ${(await dai.balanceOf(me)).toString()} dai`)

  // Post collateral for borrowing FYDai
  await weth.approve(treasury.address, MAX)
  await controller.post(ETH_A, me, me, wethForFYDai)
  console.log(`   > Posted ${wethForFYDai.toString()} weth into the Controller`)

  // Init pools and sell FYDai
  for (let name in pools) {
    const pool = pools[name].pool
    const fyDai = pools[name].fyDai
    const maturity = pools[name].maturity
    const fyDaiToSell = pools[name].fyDaiToSell

    console.log()
    console.log(`   ${name}`)
    console.log('   -----------')

    await dai.approve(pool.address, MAX)
    await pool.mint(me, me, daiReserves)
    console.log(`   > Initialized ${name} with ${(await pool.getDaiReserves()).toString()} dai`)

    await controller.borrow(ETH_A, maturity, me, me, fyDaiToSell)
    console.log(`   > Borrowed ${(await controller.debtFYDai(ETH_A, maturity, me)).toString()} ${await fyDai.symbol()} FYDai`)
    await fyDai.approve(pool.address, MAX)
    await pool.sellFYDai(me, me, fyDaiToSell)
    console.log(`   > Sold ${fyDaiToSell.toString()} ${await fyDai.symbol()} FYDai`)

    // Consider joining the Dai to vat, and recovering the ETH
  }
}