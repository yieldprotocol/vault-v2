const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const Weth = artifacts.require("WETH9");
const Treasury = artifacts.require("Treasury");
const Controller = artifacts.require("Controller");
const EthProxy = artifacts.require("EthProxy");

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();

  let wethAddress;
  let treasuryAddress;
  let controllerAddress;
  let ethProxyAddress;

  if (network !== 'development') {
    wethAddress = fixed_addrs[network].wethAddress;
  } else {
      wethAddress = (await Weth.deployed()).address;
  }

  const treasury = await Treasury.deployed();
  treasuryAddress = treasury.address;
  const controller = await Controller.deployed();
  controllerAddress = controller.address;

  // Setup EthProxy
  await deployer.deploy(
    EthProxy,
    wethAddress,
    treasuryAddress,
    controllerAddress,
  );
  ethProxyAddress = (await EthProxy.deployed()).address;
  await controller.addDelegate(ethProxyAddress);

  const deployedPeripheral = {
    'EthProxy': ethProxyAddress,
  }

  for (name in deployedPeripheral) {
    await migrations.register(web3.utils.fromAscii(name), deployedPeripheral[name]);
  }
  console.log(deployedPeripheral);
};