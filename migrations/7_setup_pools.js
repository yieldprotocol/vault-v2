const ethers = require('ethers')
const BigNumber = ethers.BigNumber

const toWad = (value) => {
  let exponent = BigNumber.from(10).pow(BigNumber.from(8))
  return BigNumber.from((value) * 10 ** 10).mul(exponent)
}

const RAY = BigNumber.from(10).pow(BigNumber.from(27))

const mulRay = (x, ray) => {
  return BigNumber.from(x).mul(BigNumber.from(ray)).div(RAY)
}

const divRay = (x, ray) => {
  return RAY.mul(BigNumber.from(x)).div(BigNumber.from(ray))
}

const Migrations = artifacts.require('Migrations')

const Vat = artifacts.require('Vat')
const Weth = artifacts.require('WETH9')
const Dai = artifacts.require('Dai')
const GemJoin = artifacts.require('GemJoin')
const EDai = artifacts.require('EDai')
const Treasury = artifacts.require('Treasury')
const Controller = artifacts.require('Controller')
const Pool = artifacts.require('Pool')

const daiReserves = toWad(10000)
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
  const treasury = await Treasury.deployed()
  const controller = await Controller.deployed()

  const eDaiToSell = (maturity, rate, daiReserves) => {
    const fromDate = Math.round((new Date()).getTime() / 1000)
    const secsToMaturity = maturity - fromDate
    const propOfYear = secsToMaturity/YEAR
    const price = Math.pow(rate, propOfYear)
    return daiReserves.mul(BigNumber.from(price)).sub(daiReserves)
  };

  const pools = {}
  let totalEDai = BigNumber.from(0)
  for (let i = 0; i < (await migrations.length()); i++) {
    const contractName = web3.utils.toAscii(await migrations.names(i))
    if (!contractName.includes('eDaiLP')) continue
    const _pool = Pool.at(await migrations.contracts(web3.utils.fromAscii(contractName)))
    const _eDai = await EDai.at(await pool.eDai())
    const _maturity = await eDai.maturity()
    const _eDaiToSell = eDaiToSell(_maturity, targetRate, daiReserves)
    totalEDai = totalEDai.add(_eDaiToSell)

    pools[contractName] = { 
      pool: _pool,
      eDai: _eDai,
      maturity: _maturity,
      eDaiToSell: _eDaiToSell,
    }
  }
  const rate = await vat.ilks(ETH_A).rate
  const spot = await vat.ilks(ETH_A).spot
  const totalDai = daiReserves.mul(pools.length())
  const normalizedDai = divRay(totalDai, rate)
  const wethForDai = mulRay(totalDai, spot)
  const wethForEDai = mulRay(totalEDai, spot)

  // Initialize pools
  await weth.deposit({ value: wethForDai.add(wethForEDai) }) // Work back how much we need for daiReserves * number of pools

  // Get Dai
  await weth.approve(wethJoin.address, MAX)  
  await wethJoin.join(me, wethForDai)
  await vat.frob(ETH_A, me, me, me, wethForDai, normalizedDai)
  await daiJoin.exit(me, totalDai)

  // Post collateral for borrowing EDai
  await weth.approve(treasury.address, MAX)
  await controller.post(ETH_A, me, me, wethForEDai)

  // Init pools and sell EDai
  for (let poolName in pools.names) {
    const pool = pools[poolName].pool
    const eDai = pools[poolName].eDai
    const maturity = pools[poolName].maturity
    const eDaiToSell = pools[poolName].eDaiToSell

    await dai.approve(pool.address, MAX)
    await pool.init(daiReserves)

    await controller.borrow(ETH_A, maturity, me, me, eDaiToSell)
    await eDai.approve(pool.address, MAX)
    await pool.sellEDai(me, me, eDaiToSell)
  }
}