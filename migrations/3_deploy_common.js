const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const Pot = artifacts.require("Pot");
const Vat = artifacts.require("Vat");
const GemJoin = artifacts.require("GemJoin");
const DaiJoin = artifacts.require("DaiJoin");
const Chai = artifacts.require("Chai");
const Treasury = artifacts.require("Treasury");
const Controller = artifacts.require("Controller");
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();

  let vatAddress;
  let wethAddress;
  let wethJoinAddress;
  let daiAddress;
  let daiJoinAddress;
  let potAddress;
  let chaiAddress;
  let treasuryAddress;
  let controllerAddress;

  if (network !== 'development') {
    vatAddress = fixed_addrs[network].vatAddress ;
    wethAddress = fixed_addrs[network].wethAddress;
    wethJoinAddress = fixed_addrs[network].wethJoinAddress;
    daiAddress = fixed_addrs[network].daiAddress;
    daiJoinAddress = fixed_addrs[network].daiJoinAddress;
    potAddress = fixed_addrs[network].potAddress;
    fixed_addrs[network].chaiAddress ? 
      (chaiAddress = fixed_addrs[network].chaiAddress)
      : (chaiAddress = (await Chai.deployed()).address);
 } else {
    vatAddress = (await Vat.deployed()).address;
    wethAddress = (await Weth.deployed()).address;
    wethJoinAddress = (await GemJoin.deployed()).address;
    daiAddress = (await ERC20.deployed()).address;
    daiJoinAddress = (await DaiJoin.deployed()).address;
    potAddress = (await Pot.deployed()).address;
    chaiAddress = (await Chai.deployed()).address;
 }

  // Setup treasury
  await deployer.deploy(
    Treasury,
    vatAddress,
    wethAddress,
    daiAddress,
    wethJoinAddress,
    daiJoinAddress,
    potAddress,
    chaiAddress,
  );
  treasury = await Treasury.deployed();
  treasuryAddress = treasury.address;

  // Setup controller
  await deployer.deploy(
    Controller,
    vatAddress,
    potAddress,
    treasuryAddress,
  );
  const controller = await Controller.deployed();
  controllerAddress = controller.address;
  await treasury.orchestrate(controllerAddress);

  // Commit addresses to migrations registry
  const deployedCore = {
    'Treasury': treasuryAddress,
    'Controller': controllerAddress,
  }

  for (name in deployedCore) {
    await migrations.register(web3.utils.fromAscii(name), deployedCore[name]);
  }
  console.log(deployedCore)
};
