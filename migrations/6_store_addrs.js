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
  let jugAddress;
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

  treasuryAddress = (await Treasury.deployed()).address;
  dealerAddress = (await Dealer.deployed()).address;
  wethOracleAddress = (await WethOracle.deployed()).address;
  chaiOracleAddress = (await ChaiOracle.deployed()).address;
  gasTokenAddress = (await GasToken.deployed()).address;
  splitterAddress = (await Splitter.deployed()).address;
  liquidationsAddress = (await Liquidations.deployed()).address;
  ethProxyAddress = (await EthProxy.deployed()).address;
  dssShutdownAddress = (await DssShutdown.deployed()).address;

  // Store External contract addresses
  const deployedExternal = {
    'Vat': vatAddress,
    'Weth': wethAddress,
    'WethJoin': wethJoinAddress,
    'Dai': daiAddress,
    'DaiJoin': daiJoinAddress,
    'Jug': jugAddress,
    'Pot': potAddress,
    'End': endAddress,
    'Chai': chaiAddress,
    'GasToken': gasTokenAddress,
  }

  // Store Core contract addresses
  const deployedCore = {
    'WethOracle': wethOracleAddress,
    'ChaiOracle': chaiOracleAddress,
    'Treasury': treasuryAddress,
    'Dealer': dealerAddress,
  }

  // Store Peripheral contract addresses
  const deployedPeripheral = {
    'Splitter': splitterAddress,
    'Liquidations': liquidationsAddress,
    'EthProxy': ethProxyAddress,
    'DssShutdown': dssShutdownAddress,
  }

  const contracts = Object.assign({}, deployedExternal, deployedCore, deployedPeripheral);
  for (name in contracts) {
    await migrations.register(web3.utils.fromAscii(name), contracts[name]);
  }
}
