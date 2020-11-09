const fixed_addrs = require('./fixed_addrs.json')

const Migrations = artifacts.require('Migrations')
const BorrowProxy = artifacts.require('BorrowProxy')
const PoolProxy = artifacts.require('PoolProxy')

module.exports = async (deployer, network) => {
  const wethAddress = fixed_addrs[network].wethAddress
  const daiAddress = fixed_addrs[network].daiAddress
  const chaiAddress = fixed_addrs[network].chaiAddress
  const treasuryAddress = fixed_addrs[network].treasuryAddress
  const controllerAddress = fixed_addrs[network].controllerAddress
  const proxyFactoryAddress = fixed_addrs[network].proxyFactoryAddress
  const proxyRegistryAddress = fixed_addrs[network].proxyRegistryAddress

  await deployer.deploy(BorrowProxy, wethAddress, daiAddress, treasuryAddress, controllerAddress)
  const borrowProxy = await BorrowProxy.deployed()

  await deployer.deploy(PoolProxy, daiAddress, chaiAddress, treasuryAddress, controllerAddress)
  const poolProxy = await PoolProxy.deployed()

  const deployment = {
    ProxyFactory: proxyFactoryAddress,
    ProxyRegistry: proxyRegistryAddress,
    BorrowProxy: borrowProxy.address,
    PoolProxy: poolProxy.address,
  }

  if (network !== 'mainnet' && network !== 'mainnet-ganache') {
    const migrations = await Migrations.at(fixed_addrs[network].migrationsAddress)
    for (name in deployment) {
      await migrations.register(web3.utils.fromAscii(name), deployment[name])
    }
  }

  console.log(deployment)
}
