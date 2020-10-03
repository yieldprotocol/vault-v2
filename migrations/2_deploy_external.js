// const { BN } = require('@openzeppelin/test-helpers');
const fixed_addrs = require('./fixed_addrs.json')
const Migrations = artifacts.require('Migrations')
const Vat = artifacts.require('Vat')
const GemJoin = artifacts.require('GemJoin')
const DaiJoin = artifacts.require('DaiJoin')
const Weth = artifacts.require('WETH9')
const Dai = artifacts.require('Dai')
const Pot = artifacts.require('Pot')
const End = artifacts.require('End')
const Chai = artifacts.require('Chai')
const { BigNumber } = require('ethers')

function toRay(value) {
  let exponent = BigNumber.from(10).pow(BigNumber.from(17))
  return BigNumber.from(value * 10 ** 10).mul(exponent)
}

function toRad(value) {
  let exponent = BigNumber.from(10).pow(BigNumber.from(35))
  return BigNumber.from(value * 10 ** 10).mul(exponent)
}

function subBN(x, y) {
  return BigNumber.from(x).sub(BigNumber.from(y))
}

const networkMap = new Map([
  ['mainnet', 1],
  ['mainnet-ganache', 1],
  ['rinkeby', 4],
  ['rinkeby-fork', 4],
  ['kovan', 42],
  ['kovan-fork', 42],
  ['goerli', 5],
  ['goerli-fork', 5],
  ['development', 31337],
])

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed()

  let vatAddress
  let wethAddress
  let wethJoinAddress
  let daiAddress
  let daiJoinAddress
  let potAddress
  let endAddress
  let chaiAddress

  if (network !== 'mainnet' && network !== 'mainnet-ganache') {
    // Setting up Vat
    const MAX = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff'
    const WAD = '000000000000000000'
    const WETH = web3.utils.fromAscii('ETH-A')
    const Line = web3.utils.fromAscii('Line')
    const spotName = web3.utils.fromAscii('spot')
    const linel = web3.utils.fromAscii('line')

    const spot = toRay(300)
    const me = (await web3.eth.getAccounts())[0]

    // Setup vat
    await deployer.deploy(Vat)
    const vat = await Vat.deployed()
    vatAddress = vat.address
    await vat.init(WETH)
    await vat.file(WETH, spotName, spot)
    await vat.file(WETH, linel, MAX)
    await vat.file(Line, MAX)
    await vat.fold(WETH, me, "20000000" + WAD)
    
    await deployer.deploy(Weth)
    wethAddress = (await Weth.deployed()).address

    await deployer.deploy(GemJoin, vatAddress, WETH, wethAddress)
    wethJoinAddress = (await GemJoin.deployed()).address

    await deployer.deploy(Dai, networkMap.get(network))
    const dai = await Dai.deployed()
    daiAddress = dai.address

    await deployer.deploy(DaiJoin, vatAddress, daiAddress)
    daiJoinAddress = (await DaiJoin.deployed()).address

    // Setup pot
    await deployer.deploy(Pot, vatAddress)
    const pot = await Pot.deployed()
    potAddress = pot.address
    await pot.setChi("1030000000" + WAD)

    // Setup end
    await deployer.deploy(End)
    const end = await End.deployed()
    endAddress = end.address
    await end.file(web3.utils.fromAscii('vat'), vatAddress)

    // Setup chai
    await deployer.deploy(Chai, vatAddress, potAddress, daiJoinAddress, daiAddress)
    chaiAddress = (await Chai.deployed()).address

    // Permissions
    await vat.rely(vatAddress)
    await vat.rely(wethJoinAddress)
    await vat.rely(daiJoinAddress)
    await vat.rely(potAddress)
    await vat.rely(endAddress)
    await dai.rely(daiJoinAddress)
  } else {
    vatAddress = fixed_addrs[network].vatAddress
    wethAddress = fixed_addrs[network].wethAddress
    wethJoinAddress = fixed_addrs[network].wethJoinAddress
    daiAddress = fixed_addrs[network].daiAddress
    daiJoinAddress = fixed_addrs[network].daiJoinAddress
    potAddress = fixed_addrs[network].potAddress
    endAddress = fixed_addrs[network].endAddress
    chaiAddress = fixed_addrs[network].chaiAddress
  }

  // Commit addresses to migrations registry
  const deployedExternal = {
    Vat: vatAddress,
    Weth: wethAddress,
    WethJoin: wethJoinAddress,
    Dai: daiAddress,
    DaiJoin: daiJoinAddress,
    Pot: potAddress,
    End: endAddress,
    Chai: chaiAddress,
  }

  for (name in deployedExternal) {
    await migrations.register(web3.utils.fromAscii(name), deployedExternal[name])
  }
  console.log(deployedExternal)
}
