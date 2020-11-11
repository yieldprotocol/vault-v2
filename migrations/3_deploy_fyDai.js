const fixed_addrs = require('./fixed_addrs.json')

const Migrations = artifacts.require('Migrations')

const Vat = artifacts.require('Vat')
const Weth = artifacts.require('WETH9')
const Dai = artifacts.require('Dai')
const GemJoin = artifacts.require('GemJoin')
const DaiJoin = artifacts.require('DaiJoin')
const Pot = artifacts.require('Pot')
const Chai = artifacts.require('Chai')

const Treasury = artifacts.require('Treasury')
const FYDai = artifacts.require('FYDai')

module.exports = async (deployer, network) => {
  const migrations = await Migrations.deployed()

  let vatAddress
  let wethAddress
  let wethJoinAddress
  let daiAddress
  let daiJoinAddress
  let potAddress
  let chaiAddress
  let treasuryAddress

  const toDate = (timestamp) => new Date(timestamp * 1000).toISOString().slice(0, 10)
  const toTimestamp = (date) => new Date(date).getTime() / 1000 + 86399
  const toSymbol = (date) => {
    const d = new Intl.DateTimeFormat('en', { year: 'numeric' }).format(new Date(date)).slice(2) +
      new Intl.DateTimeFormat('en', { month: 'short' }).format(new Date(date))
    if (network !== 'mainnet') 
      return d + new Intl.DateTimeFormat('en', { day: 'numeric' }).format(new Date(date))
    else return d
  }

  let dates = ['2020-12-31', '2021-03-31', '2021-06-30', '2021-09-30', '2021-12-31']
  let maturities = dates.map(toTimestamp)

  if (network === 'mainnet' || network === 'mainnet-ganache') {
    vatAddress = fixed_addrs[network].vatAddress
    wethAddress = fixed_addrs[network].wethAddress
    wethJoinAddress = fixed_addrs[network].wethJoinAddress
    daiAddress = fixed_addrs[network].daiAddress
    daiJoinAddress = fixed_addrs[network].daiJoinAddress
    potAddress = fixed_addrs[network].potAddress
    chaiAddress = fixed_addrs[network].chaiAddress
  } else {
    vatAddress = (await Vat.deployed()).address
    wethAddress = (await Weth.deployed()).address
    wethJoinAddress = (await GemJoin.deployed()).address
    daiAddress = (await Dai.deployed()).address
    daiJoinAddress = (await DaiJoin.deployed()).address
    potAddress = (await Pot.deployed()).address
    chaiAddress = (await Chai.deployed()).address
  }

  if (network !== 'mainnet') {
    const block = await web3.eth.getBlockNumber()
    maturities.unshift((await web3.eth.getBlock(block)).timestamp + 86400)
    maturities.unshift((await web3.eth.getBlock(block)).timestamp + 3600)
  }

  // Setup treasury
  await deployer.deploy(
    Treasury,
    vatAddress,
    wethAddress,
    daiAddress,
    wethJoinAddress,
    daiJoinAddress,
    potAddress,
    chaiAddress
  )

  const treasury = await Treasury.deployed()
  treasuryAddress = treasury.address

  const deployedFYDais = {}

  for (i in maturities) {
    fyDaiMaturity = maturities[i]
    fyDaiName = `Yield Dai - ${toDate(maturities[i])}`
    fyDaiSymbol = `fyDai${toSymbol(toDate(maturities[i]))}`

    // Setup FYDai
    await deployer.deploy(FYDai, treasuryAddress, fyDaiMaturity, fyDaiName, fyDaiSymbol)
    const fyDai = await FYDai.deployed()
    deployedFYDais[fyDaiSymbol] = fyDai.address
  }
  for (name in deployedFYDais) {
    await migrations.register(web3.utils.fromAscii(name), deployedFYDais[name])
  }
  console.log(deployedFYDais)
}
