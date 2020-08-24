const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Vat = artifacts.require("Vat");
const GemJoin = artifacts.require("GemJoin");
const DaiJoin = artifacts.require("DaiJoin");
const Pot = artifacts.require("Pot");
const Treasury = artifacts.require("Treasury");
const YDai = artifacts.require("YDai");
const Controller = artifacts.require("Controller");
const Pool = artifacts.require("Pool");
const EthProxy = artifacts.require("EthProxy");
const Splitter = artifacts.require("Splitter");
const LimitPool = artifacts.require("LimitPool");
const DaiProxy = artifacts.require("DaiProxy");


module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();

  let wethAddress;
  let treasuryAddress;
  let controllerAddress;
  let ethProxyAddress;

  let vatAddress;
  let daiAddress;

  if (network !== 'development') {
    vatAddress = fixed_addrs[network].vatAddress ;
    wethAddress = fixed_addrs[network].wethAddress;
    wethJoinAddress = fixed_addrs[network].wethJoinAddress;
    daiAddress = fixed_addrs[network].daiAddress;
    daiJoinAddress = fixed_addrs[network].daiJoinAddress;
    potAddress = fixed_addrs[network].potAddress;
  } else {
    vatAddress = (await Vat.deployed()).address;
    wethAddress = (await Weth.deployed()).address;
    wethJoinAddress = (await GemJoin.deployed()).address;
    daiAddress = (await ERC20.deployed()).address;
    daiJoinAddress = (await DaiJoin.deployed()).address;
    potAddress = (await Pot.deployed()).address;
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
  await migrations.register(web3.utils.fromAscii('EthProxy'), ethProxyAddress);
  console.log('EthProxy', ethProxyAddress);

  // Setup LimitPool
  await deployer.deploy(LimitPool);
  limitPoolAddress = (await LimitPool.deployed()).address;
  await migrations.register(web3.utils.fromAscii('LimitPool'), limitPoolAddress);
  console.log('LimitPool', limitPoolAddress);

  // Setup DaiProxy
  const yDaiNames = ['yDai0', 'yDai1', 'yDai2', 'yDai3'];
  const poolAddresses = []

  for (yDaiName of yDaiNames) {
    yDaiAddress = await migrations.contracts(web3.utils.fromAscii(yDaiName));
    yDai = await YDai.at(yDaiAddress);
    yDaiFullName = await yDai.name();
    poolAddress = await migrations.contracts(web3.utils.fromAscii( yDaiFullName + '-Pool') );
    poolAddresses.push(poolAddress)
  }
  await deployer.deploy(
    DaiProxy,
    daiAddress,
    controllerAddress,
    poolAddresses,
  );
  daiProxyAddress = (await DaiProxy.deployed()).address;

  await migrations.register(web3.utils.fromAscii('DaiProxy'), daiProxyAddress);
  console.log('DaiProxy', daiProxyAddress);

  await deployer.deploy(
    Splitter,
    vatAddress,
    wethAddress,
    daiAddress,
    wethJoinAddress,
    daiJoinAddress,
    treasuryAddress,
    controllerAddress,
    poolAddresses,
  );
  splitterAddress = (await Splitter.deployed()).address;

  await migrations.register(web3.utils.fromAscii('Splitter'), splitterAddress);
  console.log('Splitter', splitterAddress);
};
