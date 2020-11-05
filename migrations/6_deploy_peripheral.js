const Migrations = artifacts.require('Migrations')
const Weth = artifacts.require('WETH9')
const Dai = artifacts.require('Dai')
const Chai = artifacts.require('Chai')
const Treasury = artifacts.require('Treasury')
const Controller = artifacts.require('Controller')
const BorrowProxy = artifacts.require('BorrowProxy')
const PoolProxy = artifacts.require('PoolProxy')
const DSProxyFactory = artifacts.require('DSProxyFactory')
const DSProxyRegistry = artifacts.require('ProxyRegistry')

module.exports = async (deployer, network) => {
  const migrations = await Migrations.deployed()

  let daiAddress, chaiAddress, proxyFactoryAddress, proxyRegistryAddress
  if (network === 'mainnet' || network === 'mainnet-ganache') {
    wethAddress = fixed_addrs[network].wethAddress
    daiAddress = fixed_addrs[network].daiAddress
    chaiAddress = fixed_addrs[network].chaiAddress
    proxyFactoryAddress = fixed_addrs[network].proxyFactoryAddress
    proxyRegistryAddress = fixed_addrs[network].proxyRegistryAddress
  } else {
    wethAddress = (await Weth.deployed()).address
    daiAddress = (await Dai.deployed()).address
    chaiAddress = (await Chai.deployed()).address

    // Setup DSProxyFactory and DSProxyRegistry
    proxyFactoryAddress = (await deployer.deploy(DSProxyFactory)).address
    proxyRegistryAddress = (await deployer.deploy(DSProxyRegistry, proxyFactoryAddress)).address
  }
  const treasuryAddress = (await Treasury.deployed()).address
  const controllerAddress = (await Controller.deployed()).address

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
    for (name in deployment) {
      await migrations.register(web3.utils.fromAscii(name), deployment[name])
    }
  }
  
  console.log(deployment)
}
