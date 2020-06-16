const fixed_addrs = require('./fixed_addrs.json');
const Pot = artifacts.require("Pot");
const Vat = artifacts.require("Vat");

const Treasury = artifacts.require("Treasury");
const Dealer = artifacts.require("Dealer");

const YDai = artifacts.require("YDai");

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
  let potAddress;
  let treasuryAddress;
  let dealerAddress;

  if (network !== 'development') {
    vatAddress = fixed_addrs[network].vatAddress;
    potAddress = fixed_addrs[network].potAddress;
  } else {
    vatAddress = (await Vat.deployed()).address;
    potAddress = (await Pot.deployed()).address;
  }

  const treasury = await Treasury.deployed();
  treasuryAddress = treasury.address;
  const dealer = await Dealer.deployed();
  dealerAddress = dealer.address;
  
  // const block = await web3.eth.getBlockNumber();
  const maturitiesInput = new Set([
    // [(await web3.eth.getBlock(block)).timestamp + 1000, 'Name1','Symbol1'],
    [1601510399, 'yDai-2020-09-30', 'yDai-2020-09-30'],
    [1609459199, 'yDai-2020-12-31', 'yDai-2020-12-31'],
    [1617235199, 'yDai-2021-03-31', 'yDai-2021-03-31'],
    [1625097599, 'yDai-2021-06-30', 'yDai-2021-06-30'],
  ]);

  const deployedMaturities = [];
  for (const [maturity, name, symbol] of maturitiesInput.values()) {
    // Setup YDai
    await deployer.deploy(
      YDai,
      vatAddress,
      potAddress,
      treasuryAddress,
      maturity,
      name,
      symbol,
    );
    const yDai = await YDai.deployed();
    await treasury.grantAccess(yDai.address);
    await yDai.grantAccess(dealerAddress);
    await dealer.addSeries(yDai.address);

    deployedMaturities.push({
      maturity, 
      name, 
      symbol, 
      'YDai': yDai.address,
    })

    let maturityRef = db.collection(networkId.toString()).doc(name);
    batch.set(maturityRef, deployedMaturities[deployedMaturities.length -1]);
  }

  console.log(deployedMaturities);
};