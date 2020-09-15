const Migrations = artifacts.require("Migrations");
const Controller = artifacts.require("Controller");
const YieldProxy = artifacts.require("YieldProxy");

module.exports = async (deployer, network) => {
  const migrations = await Migrations.deployed();

  const controller = await Controller.deployed();
  const controllerAddress = controller.address;

  const numEDais = network !== 'mainnet' ? 5 : 4
  const pools = await Promise.all([...Array(numEDais).keys()].map(async (index) => {
    return await migrations.contracts(web3.utils.fromAscii( 'eDai' + index + '-Pool') );
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
