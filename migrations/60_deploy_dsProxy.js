const fixed_addrs = require('./fixed_addrs.json')

const Migrations = artifacts.require('Migrations')
const DSProxyFactory = artifacts.require('DSProxyFactory')
const DSProxyRegistry = artifacts.require('ProxyRegistry')

module.exports = async (deployer, network) => {

  let proxyFactoryAddress, proxyRegistryAddress
  if (network === 'development') {
    await deployer.deploy(DSProxyFactory)
    proxyFactoryAddress = (await DSProxyFactory.deployed()).address
    await deployer.deploy(DSProxyRegistry, proxyFactoryAddress)
    proxyRegistryAddress = (await DSProxyRegistry.deployed()).address
  } else {
    proxyFactoryAddress = fixed_addrs[network].proxyFactoryAddress
    proxyRegistryAddress = fixed_addrs[network].proxyRegistryAddress  
  }

  const deployment = {
    ProxyFactory: proxyFactoryAddress,
    ProxyRegistry: proxyRegistryAddress,
  }

  let migrations
  if (network === 'kovan' && network === 'kovan-fork') {
    migrations = await Migrations.at(fixed_addrs[network].migrationsAddress)
  } else if (network === 'development') {
    migrations = await Migrations.deployed()
  }

  if (migrations !== undefined) {
    for (name in deployment) {
      await migrations.register(web3.utils.fromAscii(name), deployment[name])
    }
  }

  console.log(deployment)
}
