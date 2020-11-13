const fixed_addrs = require('./fixed_addrs.json')

const Migrations = artifacts.require('Migrations')
const Controller = artifacts.require('Controller')
const DSProxyFactory = artifacts.require('DSProxyFactory')
const DSProxyRegistry = artifacts.require('ProxyRegistry')
const PoolProxy = artifacts.require('PoolProxy')

module.exports = async (deployer, network) => {

  let controllerAddress, proxyFactoryAddress, proxyRegistryAddress
  if (network === 'development') {
    controllerAddress = (await Controller.deployed()).address
    proxyFactoryAddress = (await DSProxyFactory.deployed()).address
    proxyRegistryAddress = (await DSProxyRegistry.deployed()).address
  } else {
    controllerAddress = fixed_addrs[network].controllerAddress
    proxyFactoryAddress = fixed_addrs[network].proxyFactoryAddress
    proxyRegistryAddress = fixed_addrs[network].proxyRegistryAddress  
  }

  await deployer.deploy(PoolProxy, controllerAddress)
  const poolProxy = await PoolProxy.deployed()

  const deployment = {
    PoolProxy: poolProxy.address,
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
