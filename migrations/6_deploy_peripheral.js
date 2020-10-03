const Migrations = artifacts.require('Migrations')
const Controller = artifacts.require('Controller')
const YieldProxy = artifacts.require('YieldProxy')

module.exports = async (deployer, network) => {
  const migrations = await Migrations.deployed()

  const controller = await Controller.deployed()
  const controllerAddress = controller.address

  const poolAddresses = []
  for (let i = 0; i < (await migrations.length()); i++) {
    const contractName = web3.utils.toAscii(await migrations.names(i))
    if (contractName.includes('fyDaiLP'))
      poolAddresses.push(await migrations.contracts(web3.utils.fromAscii(contractName)))
  }

  await deployer.deploy(YieldProxy, controllerAddress, poolAddresses)
  const yieldProxy = await YieldProxy.deployed()

  const deployment = {
    YieldProxy: yieldProxy.address,
  }

  for (name in deployment) {
    await migrations.register(web3.utils.fromAscii(name), deployment[name])
  }
  console.log(deployment)
}
