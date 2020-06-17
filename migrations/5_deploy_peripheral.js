const fixed_addrs = require('./fixed_addrs.json');
const Pot = artifacts.require("Pot");
const Vat = artifacts.require("Vat");
const GemJoin = artifacts.require("GemJoin");
const DaiJoin = artifacts.require("DaiJoin");
const End = artifacts.require("End");
const Chai = artifacts.require("Chai");
const GasToken = artifacts.require("GasToken1");
const Treasury = artifacts.require("Treasury");
const ChaiOracle = artifacts.require("ChaiOracle");
const WethOracle = artifacts.require("WethOracle");
const Dealer = artifacts.require("Dealer");
const Splitter = artifacts.require("Splitter");
const DssShutdown = artifacts.require("DssShutdown");
const EthProxy = artifacts.require("EthProxy");
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");

// const YDai = artifacts.require("YDai");


module.exports = async (deployer, network, accounts) => {

  let vatAddress;
  let wethAddress;
  let wethJoinAddress;
  let daiAddress;
  let daiJoinAddress;
  let potAddress;
  let endAddress;
  let chaiAddress;
  let gasTokenAddress;
  let treasuryAddress;
  let chaiOracleAddress;
  let wethOracleAddress;
  let dealerAddress;
  let splitterAddress;
  let dssShutdownAddress;
  let ethProxyAddress;

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

  const deployedPeripheral = {
    'Splitter': splitterAddress,
    'DssShutdown': dssShutdownAddress,
    'EthProxy': ethProxyAddress,
  }
  console.log(deployedPeripheral);
};