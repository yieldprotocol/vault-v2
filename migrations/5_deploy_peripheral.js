const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const Vat = artifacts.require("Vat");
const Weth = artifacts.require("WETH9");
const GemJoin = artifacts.require("GemJoin");
const ERC20 = artifacts.require("TestERC20");
const DaiJoin = artifacts.require("DaiJoin");
const Pot = artifacts.require("Pot");
const End = artifacts.require("End");
const Chai = artifacts.require("Chai");
const GasToken = artifacts.require("GasToken1");
const ChaiOracle = artifacts.require("ChaiOracle");
const WethOracle = artifacts.require("WethOracle");
const Treasury = artifacts.require("Treasury");
const Dealer = artifacts.require("Dealer");
const Liquidations = artifacts.require("Liquidations");
const Splitter = artifacts.require("Splitter");
const EthProxy = artifacts.require("EthProxy");
const DssShutdown = artifacts.require("DssShutdown");


module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();

  let vatAddress;
  let wethAddress;
  let wethJoinAddress;
  let daiAddress;
  let daiJoinAddress;
  let potAddress;
  let endAddress;
  let chaiAddress;
  let gasTokenAddress;
  let chaiOracleAddress;
  let wethOracleAddress;
  let treasuryAddress;
  let dealerAddress;
  let splitterAddress;
  let liquidationsAddress;
  let ethProxyAddress;
  let dssShutdownAddress;

  const auctionTime = 3600; // TODO: Think where to store this parameter.

  if (network !== 'development') {
    vatAddress = fixed_addrs[network].vatAddress ;
    wethAddress = fixed_addrs[network].wethAddress;
    wethJoinAddress = fixed_addrs[network].wethJoinAddress;
    daiAddress = fixed_addrs[network].daiAddress;
    daiJoinAddress = fixed_addrs[network].daiJoinAddress;
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
      potAddress = (await Pot.deployed()).address;
      endAddress = (await End.deployed()).address;
      chaiAddress = (await Chai.deployed()).address;
  }

  const treasury = await Treasury.deployed();
  treasuryAddress = treasury.address;
  wethOracleAddress = (await WethOracle.deployed()).address;
  chaiOracleAddress = (await ChaiOracle.deployed()).address;
  gasTokenAddress = (await GasToken.deployed()).address;
  const dealer = await Dealer.deployed();
  dealerAddress = dealer.address;

  // Setup Splitter
  await deployer.deploy(
    Splitter,
    treasuryAddress,
    dealerAddress,
  );
  splitterAddress = (await Splitter.deployed()).address;
  await dealer.grantAccess(splitterAddress);
  await treasury.grantAccess(splitterAddress);

  // Setup Liquidations
  await deployer.deploy(
    Liquidations,
    daiAddress,
    treasuryAddress,
    dealerAddress,
    auctionTime,
  )
  liquidationsAddress = (await Liquidations.deployed()).address;
  await dealer.grantAccess(liquidationsAddress);
  await treasury.grantAccess(liquidationsAddress);

  // Setup DssShutdown
  await deployer.deploy(
    DssShutdown,
    vatAddress,
    daiJoinAddress,
    wethAddress,
    wethJoinAddress,
    endAddress,
    chaiAddress,
    chaiOracleAddress,
    treasuryAddress,
    dealerAddress,
    liquidationsAddress,
  );
  dssShutdownAddress = (await DssShutdown.deployed()).address;
  await dealer.grantAccess(dssShutdownAddress);
  await treasury.grantAccess(dssShutdownAddress);
  await treasury.registerDssShutdown(dssShutdownAddress);
  // TODO: Retrieve the addresses for yDai contracts
  // await yDai1.grantAccess(dssShutdownAddress);
  // await yDai2.grantAccess(dssShutdownAddress);

  // Setup EthProxy
  await deployer.deploy(
    EthProxy,
    wethAddress,
    gasTokenAddress,
    dealerAddress,
  );
  ethProxyAddress = (await EthProxy.deployed()).address;
  await dealer.addProxy(ethProxyAddress);
  
  const deployedPeripheral = {
    'Splitter': splitterAddress,
    'Liquidations': liquidationsAddress,
    'DssShutdown': dssShutdownAddress,
    'EthProxy': ethProxyAddress,
  }

  for (name in deployedPeripheral) {
    await migrations.register(web3.utils.fromAscii(name), deployedPeripheral[name]);
  }
  console.log(deployedPeripheral);
};