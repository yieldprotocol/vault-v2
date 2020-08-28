const { id } = require('ethers/lib/utils')
const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const End = artifacts.require("End");
const Treasury = artifacts.require("Treasury");
const Controller = artifacts.require("Controller");
const Unwind = artifacts.require("Unwind");
const Liquidations = artifacts.require("Liquidations");
const YDai = artifacts.require("YDai");

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();
  
  let endAddress;
  let treasuryAddress;
  let controllerAddress;
  let unwindAddress;
  let liquidationsAddress;

  if (network !== 'development') {
    endAddress = fixed_addrs[network].endAddress;
 } else {
    endAddress = (await End.deployed()).address;
 }

  treasury = await Treasury.deployed();
  treasuryAddress = treasury.address;

  let numYDais = network === 'development' ? 5 : 4
  let yDais = await Promise.all([...Array(numYDais).keys()].map(async (index) => {
      return await migrations.contracts(web3.utils.fromAscii('yDai' + index))
  }))

  // Setup controller
  await deployer.deploy(
    Controller,
    treasuryAddress,
    yDais,
  );
  const controller = await Controller.deployed();
  controllerAddress = controller.address;
  const treasuryFunctions = ['pushDai', 'pullDai', 'pushChai', 'pullChai', 'pushWeth', 'pullWeth'].map(func => id(func + '(address,uint256)'))
  await treasury.batchOrchestrate(controllerAddress, treasuryFunctions)

  // Setup Liquidations
  await deployer.deploy(
    Liquidations,
    controllerAddress,
  )
  const liquidations = await Liquidations.deployed()
  liquidationsAddress = liquidations.address;
  await controller.orchestrate(liquidationsAddress, id('erase(bytes32,address)'))
  
  // Setup Unwind
  await deployer.deploy(
    Unwind,
    endAddress,
    liquidationsAddress,
  );
  const unwind = await Unwind.deployed();
  unwindAddress = unwind.address;
  await controller.orchestrate(unwind.address, id('erase(bytes32,address)'))
  await liquidations.orchestrate(unwind.address, id('erase(address)'))
  await treasury.registerUnwind(unwindAddress);

  // YDai orchestration
  for (const addr of yDais) {
      const yDai = await YDai.at(addr)
      await treasury.orchestrate(addr, id('pullDai(address,uint256)'))

      await yDai.batchOrchestrate(
          controller.address,
          [
              id('mint(address,uint256)'),
              id('burn(address,uint256)'),
          ]
      )
      await yDai.orchestrate(unwind.address, id('burn(address,uint256)'))
  }

  // Commit addresses to migrations registry
  const deployedCore = {
    'Treasury': treasuryAddress,
    'Controller': controllerAddress,
    'Unwind': unwindAddress,
    'Liquidations': liquidationsAddress,
  }

  for (name in deployedCore) {
    await migrations.register(web3.utils.fromAscii(name), deployedCore[name]);
  }
  console.log(deployedCore)
};
