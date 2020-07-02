const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const Pot = artifacts.require("Pot");
const Vat = artifacts.require("Vat");
const GemJoin = artifacts.require("GemJoin");
const DaiJoin = artifacts.require("DaiJoin");
const Chai = artifacts.require("Chai");
const GasToken = artifacts.require("GasToken1");
const WethOracle = artifacts.require("WethOracle");
const ChaiOracle = artifacts.require("ChaiOracle");
const Treasury = artifacts.require("Treasury");
const Dealer = artifacts.require("Dealer");
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
  let gasTokenAddress;
  let wethOracleAddress;
  let chaiOracleAddress;
  let treasuryAddress;
  let dealerAddress;

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
    fixed_addrs[network].gasTokenAddress ? 
      (gasTokenAddress = fixed_addrs[network].gasTokenAddress)
      : (gasTokenAddress = (await GasToken.deployed()).address);
 } else {
    vatAddress = (await Vat.deployed()).address;
    wethAddress = (await Weth.deployed()).address;
    wethJoinAddress = (await GemJoin.deployed()).address;
    daiAddress = (await ERC20.deployed()).address;
    daiJoinAddress = (await DaiJoin.deployed()).address;
    potAddress = (await Pot.deployed()).address;
    chaiAddress = (await Chai.deployed()).address;
    gasTokenAddress = (await GasToken.deployed()).address;
 }

  // Setup chaiOracle
  await deployer.deploy(ChaiOracle, potAddress);
  chaiOracleAddress = (await ChaiOracle.deployed()).address;

  // Setup wethOracle
  await deployer.deploy(WethOracle, vatAddress);
  wethOracleAddress = (await WethOracle.deployed()).address;

  // Setup treasury
  // TODO: The Treasury constructor reverts on `_dai.approve(chai_, uint256(-1));`
  await deployer.deploy(
    Treasury,
    daiAddress,        // dai
    chaiAddress,       // chai
    chaiOracleAddress, // chaiOracle
    wethAddress,       // weth
    daiJoinAddress,    // daiJoin
    wethJoinAddress,   // wethJoin
    vatAddress,        // vat
  );
  treasury = await Treasury.deployed();
  treasuryAddress = treasury.address;

  // Setup dealer
  await deployer.deploy(
    Dealer,
    vatAddress,
    wethAddress,
    daiAddress,
    potAddress,
    chaiAddress,
    gasTokenAddress,
    treasuryAddress,
  );
  const dealer = await Dealer.deployed();
  dealerAddress = dealer.address;
  await treasury.orchestrate(dealerAddress);

  // Commit addresses to migrations registry
  const deployedCore = {
    'WethOracle': wethOracleAddress,
    'ChaiOracle': chaiOracleAddress,
    'Treasury': treasuryAddress,
    'Dealer': dealerAddress,
  }

  for (name in deployedCore) {
    await migrations.register(web3.utils.fromAscii(name), deployedCore[name]);
  }
  console.log(deployedCore)
};
