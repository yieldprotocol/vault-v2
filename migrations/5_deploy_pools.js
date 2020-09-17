const fixed_addrs = require('./fixed_addrs.json')

const Migrations = artifacts.require('Migrations')
const Dai = artifacts.require('Dai')
const EDai = artifacts.require('EDai')
const Pool = artifacts.require('Pool')

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed()

  let daiAddress

  if (network === 'mainnet' || network === 'mainnet-ganache') {
    daiAddress = fixed_addrs[network].daiAddress
  } else {
    daiAddress = (await Dai.deployed()).address
  }

  const eDaiAddresses = []
  const deployedPools = {}

  for (let i = 0; i < (await migrations.length()); i++) {
    const contractName = web3.utils.toAscii(await migrations.names(i))
    if (contractName.includes('eDai'))
      eDaiAddresses.push(await migrations.contracts(web3.utils.fromAscii(contractName)))
  }

  for (let i = 0; i < (await migrations.length()); i++) {
    const contractName = web3.utils.toAscii(await migrations.names(i))
    if (!contractName.includes('eDai')) continue
    eDai = await EDai.at(await migrations.contracts(web3.utils.fromAscii(contractName)))
    poolName = (await eDai.name()) + '-Pool'
    poolSymbol = (await eDai.symbol()).replace('eDai', 'eDaiLP')

    await deployer.deploy(Pool, daiAddress, eDai.address, poolName, poolSymbol)
    pool = await Pool.deployed()
    deployedPools[poolSymbol] = pool.address
  }

  for (name in deployedPools) {
    await migrations.register(web3.utils.fromAscii(name), deployedPools[name])
  }
  console.log(deployedPools)
}
