const Migrations = artifacts.require('Migrations')
const Dai = artifacts.require('Dai')
const Chai = artifacts.require('Chai')
const Treasury = artifacts.require('Treasury')
const Controller = artifacts.require('Controller')
const PoolProxy = artifacts.require('PoolProxy')

module.exports = async (deployer, network) => {
  const migrations = await Migrations.deployed()

  let daiAddress, chaiAddress
  if (network === 'mainnet' || network === 'mainnet-ganache') {
    daiAddress = fixed_addrs[network].daiAddress
    chaiAddress = fixed_addrs[network].chaiAddress
  } else {
    daiAddress = (await Dai.deployed()).address
    chaiAddress = (await Chai.deployed()).address
  }
  const treasuryAddress = (await Treasury.deployed()).address
  const controllerAddress = (await Controller.deployed()).address

  await deployer.deploy(PoolProxy, daiAddress, chaiAddress, treasuryAddress, controllerAddress)
  const poolProxy = await PoolProxy.deployed()

  const deployment = {
    PoolProxy: poolProxy.address,
  }

  for (name in deployment) {
    await migrations.register(web3.utils.fromAscii(name), deployment[name])
  }
  console.log(deployment)
}
