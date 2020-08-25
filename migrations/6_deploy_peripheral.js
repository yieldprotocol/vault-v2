const Migrations = artifacts.require("Migrations");
const Controller = artifacts.require("Controller");
const YieldProxy = artifacts.require("YieldProxy");
const YDai = artifacts.require("YDai");

module.exports = async (deployer) => {
  const migrations = await Migrations.deployed();

  const controller = await Controller.deployed();
  const controllerAddress = controller.address;

  const pools = await Promise.all(['yDai0', 'yDai1', 'yDai2', 'yDai3'].map(async (yDaiName) => {
    yDaiAddress = await migrations.contracts(web3.utils.fromAscii(yDaiName));
    yDai = await YDai.at(yDaiAddress);
    yDaiFullName = await yDai.name();

    return await migrations.contracts(web3.utils.fromAscii( yDaiFullName + '-Pool') );
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
