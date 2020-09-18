const { id } = require('ethers/lib/utils')
const fixed_addrs = require('./fixed_addrs.json')
const Migrations = artifacts.require('Migrations')
const End = artifacts.require('End')
const Treasury = artifacts.require('Treasury')
const Controller = artifacts.require('Controller')
const Unwind = artifacts.require('Unwind')
const Liquidations = artifacts.require('Liquidations')
const EDai = artifacts.require('EDai')

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed()

  let endAddress
  let treasuryAddress
  let controllerAddress
  let unwindAddress
  let liquidationsAddress

  if (network === 'mainnet' || network === 'mainnet-ganache') {
    endAddress = fixed_addrs[network].endAddress
  } else {
    endAddress = (await End.deployed()).address
  }

  treasury = await Treasury.deployed()
  treasuryAddress = treasury.address

  const eDais = []
  for (let i = 0; i < (await migrations.length()); i++) {
    const contractName = web3.utils.toAscii(await migrations.names(i))
    if (contractName.includes('eDai')) eDais.push(await migrations.contracts(web3.utils.fromAscii(contractName)))
  }

  // Setup controller
  await deployer.deploy(Controller, treasuryAddress, eDais)
  const controller = await Controller.deployed()
  controllerAddress = controller.address
  const treasuryFunctions = ['pushDai', 'pullDai', 'pushChai', 'pullChai', 'pushWeth', 'pullWeth'].map((func) =>
    id(func + '(address,uint256)')
  )
  await treasury.batchOrchestrate(controllerAddress, treasuryFunctions)

  // Setup Liquidations
  await deployer.deploy(Liquidations, controllerAddress)
  const liquidations = await Liquidations.deployed()
  liquidationsAddress = liquidations.address
  await controller.orchestrate(liquidationsAddress, id('erase(bytes32,address)'))

  // Setup Unwind
  await deployer.deploy(Unwind, endAddress, liquidationsAddress)
  const unwind = await Unwind.deployed()
  unwindAddress = unwind.address
  await controller.orchestrate(unwind.address, id('erase(bytes32,address)'))
  await liquidations.orchestrate(unwind.address, id('erase(address)'))

  // EDai orchestration
  for (const addr of eDais) {
    const eDai = await EDai.at(addr)
    await treasury.orchestrate(addr, id('pullDai(address,uint256)'))

    await eDai.batchOrchestrate(controller.address, [id('mint(address,uint256)'), id('burn(address,uint256)')])
    await eDai.orchestrate(unwind.address, id('burn(address,uint256)'))
  }

  // Register Unwind at the very end. If the script fails after this point, Treasury needs to be redeployed.
  await treasury.registerUnwind(unwindAddress)

  // Commit addresses to migrations registry
  const deployedCore = {
    Treasury: treasuryAddress,
    Controller: controllerAddress,
    Unwind: unwindAddress,
    Liquidations: liquidationsAddress,
  }

  for (name in deployedCore) {
    await migrations.register(web3.utils.fromAscii(name), deployedCore[name])
  }
  console.log(deployedCore)
}
