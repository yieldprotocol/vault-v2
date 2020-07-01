const fixed_addrs = require('./fixed_addrs.json');
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
const EthProxy = artifacts.require("EthProxy");
const Unwind = artifacts.require("Unwind");

const firebase = require('firebase-admin');
let serviceAccount = require('../firebaseKey.json');
try {
  firebase.initializeApp({
    credential: firebase.credential.cert(serviceAccount),
    databaseURL: "https://yield-ydai.firebaseio.com"
  });
} catch (e) { console.log(e)}

module.exports = async (deployer, network, accounts) => {

    const db = firebase.firestore();
    const batch = db.batch();
    const networkId = await web3.eth.net.getId();

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
    let unwindAddress;
  
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
    liquidationsAddress = (await Liquidations.deployed()).address;
    ethProxyAddress = (await EthProxy.deployed()).address;
    unwindAddress = (await Unwind.deployed()).address;

    try {

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
          let externalRef = db.collection(networkId.toString()).doc('deployedExternal')
          batch.set(externalRef, deployedExternal);
          console.log('Updated External contract addresses:');
          console.log(deployedExternal);

          // Store Core contract addresses
          const deployedCore = {
            'WethOracle': wethOracleAddress,
            'ChaiOracle': chaiOracleAddress,
            'Treasury': treasuryAddress,
            'Dealer': dealerAddress,
          }
          let coreRef = db.collection(networkId.toString()).doc('deployedCore')
          batch.set(coreRef, deployedCore);
          console.log('Updated Core contract addresses:');
          console.log(deployedCore);

          // Store Peripheral contract addresses
          const deployedPeripheral = {
            'Liquidations': liquidationsAddress,
            'EthProxy': ethProxyAddress,
            'Unwind': unwindAddress,
          }

          let peripheralRef = db.collection(networkId.toString()).doc('deployedPeripheral')
          batch.set(peripheralRef, deployedPeripheral);
          console.log('Updated peripheral contract addresses:');
          console.log(deployedPeripheral);

          await batch.commit();
          console.log('All address updates executed successfully');
          firebase.app().delete();
    } 
    catch (e) {console.log(e)}
}
