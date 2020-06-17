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
  
    treasuryAddress = (await Treasury.deployed()).address;
    dealerAddress = (await Dealer.deployed()).address;
    wethOracleAddress = (await WethOracle.deployed()).address;
    chaiOracleAddress = (await ChaiOracle.deployed()).address;
    gasTokenAddress = (await GasToken.deployed()).address;
    splitterAddress = (await Splitter.deployed()).address;
    dssShutdownAddress = (await DssShutdown.deployed()).address;
    ethProxyAddress = (await EthProxy.deployed()).address;

    try {

        // Store External contract addresses
        const deployedExternal = {
            'Vat': vatAddress,
            'Weth': wethAddress,
            'WethJoin': wethJoinAddress,
            'Dai': daiAddress,
            'DaiJoin': daiJoinAddress,
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
            'Splitter': splitterAddress,
            'DssShutdown': dssShutdownAddress,
            'EthProxy': ethProxyAddress,
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
