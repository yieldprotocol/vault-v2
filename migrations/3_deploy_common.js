const fixed_addrs = require('./fixed_addrs.json');
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

const Migrations = artifacts.require("Migrations");

const admin = require('firebase-admin');
let serviceAccount = require('../firebaseKey.json');
try {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount),
    databaseURL: "https://yield-ydai.firebaseio.com"
  });
} catch (e) { console.log(e)}

module.exports = async (deployer, network, accounts) => {

  const db = admin.firestore();
  const batch = db.batch();
  const networkId = await web3.eth.net.getId();

  const migration = await Migrations.deployed();
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
    wethAddress = await migration.contracts.call('weth', (e,r)=> !e && r)
    wethJoinAddress = (await GemJoin.deployed()).address;
    daiAddress = await migration.contracts.call('dai', (e,r)=> !e && r)
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
    treasuryAddress,
    daiAddress,
    wethAddress,
    wethOracleAddress,
    chaiAddress,
    chaiOracleAddress,
    gasTokenAddress,
  );
  const dealer = await Dealer.deployed();
  dealerAddress = dealer.address;
  await treasury.grantAccess(dealerAddress);

  // Commit addresses to firebase
  const deployedCore = {
    'WethOracle': wethOracleAddress,
    'ChaiOracle': chaiOracleAddress,
    'Treasury': treasuryAddress,
    'Dealer': dealerAddress,
  }

  let coreRef = db.collection(networkId.toString()).doc('deployedCore')
  batch.set(coreRef, deployedCore);
  await batch.commit();

  console.log(deployedCore)
};
