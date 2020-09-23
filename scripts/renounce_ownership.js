const Migrations = artifacts.require('Migrations')
const Treasury = artifacts.require('Treasury')
const Controller = artifacts.require('Controller')
const Liquidations = artifacts.require('Liquidations')
const Unwind = artifacts.require('Unwind')
const EDai = artifacts.require('EDai')

module.exports = async (deployer, network) => {
  const migrations = await Migrations.deployed()
  await migrations.transferOwnership('0x000000000000000000000000000000000000dead')

  const treasury = await Treasury.deployed()
  await treasury.transferOwnership('0x000000000000000000000000000000000000dead')

  const controller = await Controller.deployed()
  await controller.transferOwnership('0x000000000000000000000000000000000000dead')

  const liquidations = await Liquidations.deployed()
  await liquidations.transferOwnership('0x000000000000000000000000000000000000dead')

  const unwind = await Unwind.deployed()
  await unwind.transferOwnership('0x000000000000000000000000000000000000dead')
  
  const eDais = []
  for (let i = 0; i < (await migrations.length()); i++) {
    const contractName = web3.utils.toAscii(await migrations.names(i))
    if (contractName.includes('eDai') && !contractName.includes('LP')) {
      const eDai = await EDai.at(await migrations.contracts(web3.utils.fromAscii(contractName)))
      await eDai.transferOwnership('0x000000000000000000000000000000000000dead')
    }
  }
}
