const Migrations = artifacts.require("Migrations");
const Controller = artifacts.require("Controller");
const YieldProxy = artifacts.require("YieldProxy");
const EDai = artifacts.require("EDai");

module.exports = async (deployer) => {
  const migrations = await Migrations.deployed();

  const controller = await Controller.deployed();
  const controllerAddress = controller.address;

  const pools = await Promise.all(['eDai0', 'eDai1', 'eDai2', 'eDai3'].map(async (eDaiName) => {
    eDaiAddress = await migrations.contracts(web3.utils.fromAscii(eDaiName));
    eDai = await EDai.at(eDaiAddress);
    eDaiFullName = await eDai.name();

    return await migrations.contracts(web3.utils.fromAscii( eDaiFullName + '-Pool') );
  }));

  await deployer.deploy(YieldProxy, controllerAddress, pools);
  const yieldProxy = await YieldProxy.deployed()

  const deployment = {
      'YieldProxy': yieldProxy.address
  }

  for (name in deployment) {
    await migrations.register(web3.utils.fromAscii(name), deployment[name]);
  }

  console.log(deployment)
};
