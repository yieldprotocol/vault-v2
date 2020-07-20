const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const Vat = artifacts.require("Vat");
const Weth = artifacts.require("WETH9");
const GemJoin = artifacts.require("GemJoin");
const ERC20 = artifacts.require("TestERC20");
const DaiJoin = artifacts.require("DaiJoin");
const Jug = artifacts.require("Jug");
const Pot = artifacts.require("Pot");
const End = artifacts.require("End");
const Chai = artifacts.require("Chai");
const Treasury = artifacts.require("Treasury");
const YDai = artifacts.require("YDai");
const Controller = artifacts.require("Controller");
const Liquidations = artifacts.require("Liquidations");
const EthProxy = artifacts.require("EthProxy");
const Unwind = artifacts.require("Unwind");
const ControllerView = artifacts.require("ControllerView");

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();

  let vatAddress;
  let wethAddress;
  let wethJoinAddress;
  let daiAddress;
  let daiJoinAddress;
  let jugAddress;
  let potAddress;
  let endAddress;
  let chaiAddress;
  let treasuryAddress;
  let controllerAddress;
  let splitterAddress;
  let liquidationsAddress;
  let ethProxyAddress;
  let unwindAddress;
  let controlerViewAddress;

  const yDaiNames = ['yDai1', 'yDai2', 'yDai3', 'yDai4']; // TODO: Consider iterating until the address returned is 0

  if (network !== 'development') {
    vatAddress = fixed_addrs[network].vatAddress ;
    wethAddress = fixed_addrs[network].wethAddress;
    wethJoinAddress = fixed_addrs[network].wethJoinAddress;
    daiAddress = fixed_addrs[network].daiAddress;
    daiJoinAddress = fixed_addrs[network].daiJoinAddress;
    jugAddress = fixed_addrs[network].jugAddress;
    potAddress = fixed_addrs[network].potAddress;
    endAddress = fixed_addrs[network].endAddress;
    fixed_addrs[network].chaiAddress ? 
      (chaiAddress = fixed_addrs[network].chaiAddress)
      : (chaiAddress = (await Chai.deployed()).address);
  } else {
      vatAddress = (await Vat.deployed()).address;
      wethAddress = (await Weth.deployed()).address;
      wethJoinAddress = (await GemJoin.deployed()).address;
      daiAddress = (await ERC20.deployed()).address;
      daiJoinAddress = (await DaiJoin.deployed()).address;
      jugAddress = (await Jug.deployed()).address;
      potAddress = (await Pot.deployed()).address;
      endAddress = (await End.deployed()).address;
      chaiAddress = (await Chai.deployed()).address;
  }

  const treasury = await Treasury.deployed();
  treasuryAddress = treasury.address;
  const controller = await Controller.deployed();
  controllerAddress = controller.address;

  // Setup Liquidations
  await deployer.deploy(
    Liquidations,
    daiAddress,
    treasuryAddress,
    controllerAddress,
  )
  liquidationsAddress = (await Liquidations.deployed()).address;
  await controller.orchestrate(liquidationsAddress);
  await treasury.orchestrate(liquidationsAddress);

  // Setup Unwind
  await deployer.deploy(
    Unwind,
    vatAddress,
    daiJoinAddress,
    wethAddress,
    wethJoinAddress,
    jugAddress,
    potAddress,
    endAddress,
    chaiAddress,
    treasuryAddress,
    controllerAddress,
    liquidationsAddress,
  );
  const unwind = await Unwind.deployed();
  unwindAddress = unwind.address;
  await controller.orchestrate(unwindAddress);
  await treasury.orchestrate(unwindAddress);
  await treasury.registerUnwind(unwindAddress);
  
  for (yDaiName of yDaiNames) {
    yDaiAddress = await migrations.contracts(web3.utils.fromAscii(yDaiName));
    const yDai = await YDai.at(yDaiAddress);
    await yDai.orchestrate(unwindAddress);
  }

  // Setup EthProxy
  await deployer.deploy(
    EthProxy,
    wethAddress,
    treasuryAddress,
    controllerAddress,
  );
  ethProxyAddress = (await EthProxy.deployed()).address;
  await controller.addDelegate(ethProxyAddress);
  
  // Setup ControllerView
  await deployer.deploy(
    ControllerView,
    vatAddress,
    potAddress,
    controllerAddress,
  );
  const controllerView = await ControllerView.deployed();
  controllerViewAddress = controllerView.address;

  const deployedPeripheral = {
    'Liquidations': liquidationsAddress,
    'Unwind': unwindAddress,
    'EthProxy': ethProxyAddress,
    'ControllerView': controllerViewAddress,
  }

  for (name in deployedPeripheral) {
    await migrations.register(web3.utils.fromAscii(name), deployedPeripheral[name]);
  }
  console.log(deployedPeripheral);
};