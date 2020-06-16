const fixed_addrs = require('./fixed_addrs.json');
const Pot = artifacts.require("Pot");
const Vat = artifacts.require("Vat");
const GemJoin = artifacts.require("GemJoin");
const DaiJoin = artifacts.require("DaiJoin");
const End = artifacts.require("End");
const Chai = artifacts.require("Chai");

const Treasury = artifacts.require("Treasury");
const ChaiOracle = artifacts.require("ChaiOracle");
const WethOracle = artifacts.require("WethOracle");
const Dealer = artifacts.require("Dealer");

const YDai = artifacts.require("YDai");

const Splitter = artifacts.require("Splitter");
const DssShutdown = artifacts.require("DssShutdown");

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

  console.log( process.argv )

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
  let endAddress;
  let chaiAddress;
  let treasuryAddress;
  let chaiOracleAddress;
  let wethOracleAddress;
  let dealerAddress;
  let splitterAddress;
  let dssShutdownAddress;

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
      wethAddress = await migration.contracts.call('weth', (e,r)=> !e && r)
      wethJoinAddress = (await GemJoin.deployed()).address;
      daiAddress = await migration.contracts.call('dai', (e,r)=> !e && r)
      daiJoinAddress = (await DaiJoin.deployed()).address;
      potAddress = (await Pot.deployed()).address;
      endAddress = (await End.deployed()).address;
      chaiAddress = (await Chai.deployed()).address;
  }

  const treasury = await Treasury.deployed();
  treasuryAddress = treasury.address;
  wethOracleAddress = (await WethOracle.deployed()).address;
  chaiOracleAddress = (await ChaiOracle.deployed()).address;
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

  const deployedPeripheral = {
    'Splitter': splitterAddress,
    'DssShutdown': dssShutdownAddress,
  }

  let peripheralRef = db.collection(networkId.toString()).doc('deployedPeripheral')
  batch.set(peripheralRef, deployedPeripheral);
  await batch.commit();

  console.log(deployedPeripheral);
};