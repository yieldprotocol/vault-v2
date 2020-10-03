const Migrations = artifacts.require('Migrations')
const Treasury = artifacts.require('Treasury')
const Controller = artifacts.require('Controller')
const Liquidations = artifacts.require('Liquidations')
const Unwind = artifacts.require('Unwind')
const FYDai = artifacts.require('FYDai')

module.exports = async (deployer, network) => {
  const migrations = await Migrations.deployed()
  await migrations.renounceOwnership()

  const treasury = await Treasury.deployed()
  await treasury.renounceOwnership()

  const controller = await Controller.deployed()
  await controller.renounceOwnership()

  const liquidations = await Liquidations.deployed()
  await liquidations.renounceOwnership()

  const unwind = await Unwind.deployed()
  await unwind.renounceOwnership()
  
  for (let i = 0; i < (await migrations.length()); i++) {
    const contractName = web3.utils.toAscii(await migrations.names(i))
    if (contractName.includes('fyDai') && !contractName.includes('LP')) {
      const fyDai = await FYDai.at(await migrations.contracts(web3.utils.fromAscii(contractName)))
      await fyDai.renounceOwnership()
    }
  }
}
