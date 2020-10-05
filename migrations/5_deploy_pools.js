const fixed_addrs = require('./fixed_addrs.json')

const Migrations = artifacts.require('Migrations')
const Dai = artifacts.require('Dai')
const FYDai = artifacts.require('FYDai')
const Pool = artifacts.require('Pool')

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed()

  let daiAddress

  if (network === 'mainnet' || network === 'mainnet-ganache') {
    daiAddress = fixed_addrs[network].daiAddress
  } else {
    daiAddress = (await Dai.deployed()).address
  }

  const fyDaiAddresses = []
  const deployedPools = {}

  for (let i = 0; i < (await migrations.length()); i++) {
    const contractName = web3.utils.toAscii(await migrations.names(i))
    if (contractName.includes('fyDai'))
      fyDaiAddresses.push(await migrations.contracts(web3.utils.fromAscii(contractName)))
  }

  for (let i = 0; i < (await migrations.length()); i++) {
    const contractName = web3.utils.toAscii(await migrations.names(i))
    if (!contractName.includes('fyDai')) continue
    fyDai = await FYDai.at(await migrations.contracts(web3.utils.fromAscii(contractName)))
    poolName = (await fyDai.name()) + '-Pool'
    poolSymbol = (await fyDai.symbol()).replace('fyDai', 'fyDaiLP')

    await deployer.deploy(Pool, daiAddress, fyDai.address, poolName, poolSymbol)
    pool = await Pool.deployed()
    deployedPools[poolSymbol] = pool.address
  }

  for (name in deployedPools) {
    await migrations.register(web3.utils.fromAscii(name), deployedPools[name])
  }
  console.log(deployedPools)
}
