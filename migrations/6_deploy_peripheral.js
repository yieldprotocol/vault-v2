const fixed_addrs = require('./fixed_addrs.json')

const Migrations = artifacts.require('Migrations')
const Dai = artifacts.require('Dai')
const Chai = artifacts.require('Chai')
const Treasury = artifacts.require('Treasury')
const Controller = artifacts.require('Controller')
const DSProxyFactory = artifacts.require('DSProxyFactory')
const DSProxyRegistry = artifacts.require('ProxyRegistry')
const BorrowProxy = artifacts.require('BorrowProxy')
const PoolProxy = artifacts.require('PoolProxy')

module.exports = async (deployer, network) => {

  let daiAddress, chaiAddress, treasuryAddress, controllerAddress, proxyFactoryAddress, proxyRegistryAddress
  if (network === 'development') {
    daiAddress = (await Dai.deployed()).address
    chaiAddress = (await Chai.deployed()).address
    treasuryAddress = (await Treasury.deployed()).address
    controllerAddress = (await Controller.deployed()).address
    
    await deployer.deploy(DSProxyFactory)
    proxyFactoryAddress = (await DSProxyFactory.deployed()).address
    await deployer.deploy(DSProxyRegistry, proxyFactoryAddress)
    proxyRegistryAddress = (await DSProxyRegistry.deployed()).address
  } else {
    daiAddress = fixed_addrs[network].daiAddress
    chaiAddress = fixed_addrs[network].chaiAddress
    treasuryAddress = fixed_addrs[network].treasuryAddress
    controllerAddress = fixed_addrs[network].controllerAddress
    proxyFactoryAddress = fixed_addrs[network].proxyFactoryAddress
    proxyRegistryAddress = fixed_addrs[network].proxyRegistryAddress  
  }

  await deployer.deploy(BorrowProxy, controllerAddress)
  const borrowProxy = await BorrowProxy.deployed()

  await deployer.deploy(PoolProxy, daiAddress, chaiAddress, treasuryAddress, controllerAddress)
  const poolProxy = await PoolProxy.deployed()

  const deployment = {
    ProxyFactory: proxyFactoryAddress,
    ProxyRegistry: proxyRegistryAddress,
    BorrowProxy: borrowProxy.address,
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
