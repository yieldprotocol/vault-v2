const fixed_addrs = require('./fixed_addrs.json');
const Pot = artifacts.require("Pot");
const Vat = artifacts.require("Vat");
const GemJoin = artifacts.require("GemJoin");
const DaiJoin = artifacts.require("DaiJoin");
const Chai = artifacts.require("Chai");

const Treasury = artifacts.require("Treasury");
const ChaiOracle = artifacts.require("ChaiOracle");
const WethOracle = artifacts.require("WethOracle");

const Migrations = artifacts.require("Migrations");

module.exports = async (deployer, network, accounts) => {

  const migration = await Migrations.deployed();
  let vatAddress;
  let wethAddress;
  let wethJoinAddress;
  let daiAddress;
  let daiJoinAddress;
  let potAddress;
  let chaiAddress;
  let treasuryAddress;
  let chaiOracleAddress;
  let wethOracleAddress;

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
    wethAddress = await migration.contracts.call('weth', (e,r)=> !e && r)
    wethJoinAddress = (await GemJoin.deployed()).address;
    daiAddress = await migration.contracts.call('dai', (e,r)=> !e && r)
    daiJoinAddress = (await DaiJoin.deployed()).address;
    potAddress = (await Pot.deployed()).address;
    chaiAddress = (await Chai.deployed()).address;
 }

  // Setup chaiOracle
  await deployer.deploy(ChaiOracle, potAddress);
  chaiOracleAddress = (await ChaiOracle.deployed()).address;

  // Setup wethOracle
  await deployer.deploy(WethOracle, vatAddress);
  wethOracleAddress = (await WethOracle.deployed()).address;

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
};
