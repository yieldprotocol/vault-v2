// const { BN } = require('@openzeppelin/test-helpers');

module.exports = async (deployer, network, accounts) => {
  if (network == "development"){
    const [ owner ] = accounts;
    console.log("Owner: " + owner);

    // Setting up Vat
    const ERC20 = artifacts.require("TestERC20");
    const Vat = artifacts.require('Vat');
    const GemJoin = artifacts.require('GemJoin');
    const DaiJoin = artifacts.require('DaiJoin');
    const Pot = artifacts.require("Pot");
    const Chai = artifacts.require("Chai");

    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let chai;

    const ilk = web3.utils.fromAscii("ETH-A");
    const Line = web3.utils.fromAscii("Line");
    const spotName = web3.utils.fromAscii("spot");
    const linel = web3.utils.fromAscii("line");

    // const limits =  toRad(1);
    // const spot  = toRay(1.5);
    // const rate  = toRay(1.25);
    const limits = "1000000000000000000000000000000000000000000000";
    const spot = "1500000000000000000000000000"
    const rate = "1250000000000000000000000000"

    // Setup Vat, Dai, Join and Weth
    await deployer.deploy(Vat);
    vat = await Vat.deployed();
    await vat.rely(vat.address);
    await vat.init(ilk); // Set ilk rate to 1.0

    await deployer.deploy(ERC20, 0);
    weth = await ERC20.deployed(); 

    await deployer.deploy(GemJoin, vat.address, ilk, weth.address);
    wethJoin = await GemJoin.deployed();
    await vat.rely(wethJoin.address);

    await deployer.deploy(ERC20, 0);
    dai = await ERC20.deployed();

    await deployer.deploy(DaiJoin, vat.address, dai.address);
    daiJoin = await DaiJoin.deployed();
    await vat.rely(daiJoin.address);

    // Setup spot and limits
    await vat.file(ilk, spotName, spot);
    await vat.file(ilk, linel, limits);
    await vat.file(Line, limits);

    // Setup Pot
    await deployer.deploy(Pot, vat.address);
    pot = await Pot.deployed();
    await vat.rely(pot.address);

    // Setup Chai
    await deployer.deploy(
        Chai,
        vat.address,
        pot.address,
        daiJoin.address,
        dai.address,
    );
    chai = await Chai.deployed();
    await vat.rely(chai.address);

    // --- TODO: Find out how to move the next section to 3_deploy, passing the addresses on
    
    const Treasury = artifacts.require("Treasury");
    const ChaiOracle = artifacts.require("ChaiOracle");
    const WethOracle = artifacts.require("WethOracle");
    let treasury;
    let chaiOracle;
    let wethOracle;

    await deployer.deploy(
      Treasury,
      dai.address,        // dai
      chai.address,       // chai
      weth.address,       // weth
      daiJoin.address,    // daiJoin
      wethJoin.address,   // wethJoin
      vat.address,        // vat
    );
    treasury = await Treasury.deployed();
    await treasury.grantAccess(owner); // Do not copy over beyond development

    // Setup chaiOracle
    await deployer.deploy(ChaiOracle, pot.address);
    chaiOracle = await ChaiOracle.deployed();

    // Setup wethOracle
    await deployer.deploy(WethOracle, vat.address);
    wethOracle = await WethOracle.deployed();

    // --- TODO: Find out how to move the next section to 4_deploy, passing the addresses on

    // Setup yDai - TODO: Replace by the right maturities, there will be several of these
    const YDai = artifacts.require("YDai");
    const Mint = artifacts.require("Mint");
    const ChaiDealer = artifacts.require("ChaiDealer");
    const WethDealer = artifacts.require("WethDealer");

    let yDai;
    let mint;
    let chaiDealer;
    let wethDealer;
    const block = await web3.eth.getBlockNumber();
    const maturitiesInput = new Set([
      [(await web3.eth.getBlock(block)).timestamp + 1000, 'Name1','Symbol1'],
      [(await web3.eth.getBlock(block)).timestamp + 2000, 'Name2','Symbol2'],
      [(await web3.eth.getBlock(block)).timestamp + 3000, 'Name3','Symbol3'],
      [(await web3.eth.getBlock(block)).timestamp + 4000, 'Name4','Symbol4'],
    ]);
    const maturitiesOutput = [];
    for (const [maturity, name, symbol] of maturitiesInput.values()) {
      // Setup YDai
      await deployer.deploy(
        YDai,
        vat.address,
        pot.address,
        maturity,
        name,
        symbol,
      );
      yDai = await YDai.deployed();

      // Setup mint
      await deployer.deploy(
        Mint,
        treasury.address,
        dai.address,
        yDai.address,
        { from: owner },
      );
      mint = await Mint.deployed();
      await yDai.grantAccess(mint.address);
      await treasury.grantAccess(mint.address);

      // Setup ChaiDealer
      await deployer.deploy(
        ChaiDealer,
        treasury.address,
        dai.address,
        yDai.address,
        chai.address,
        chaiOracle.address,
        { from: owner },
      );
      chaiDealer = await ChaiDealer.deployed();
      await yDai.grantAccess(chaiDealer.address);
      await treasury.grantAccess(chaiDealer.address);
    
      // Setup WethDealer
      await deployer.deploy(
        WethDealer,
        treasury.address,
        dai.address,
        yDai.address,
        weth.address,
        wethOracle.address,
      );
      wethDealer = await WethDealer.deployed();
      await yDai.grantAccess(wethDealer.address);
      await treasury.grantAccess(wethDealer.address);

      maturitiesOutput.push(new Map([
        ['maturity', maturity],
        ['name', name],
        ['symbol', symbol],
        ['YDai', yDai.address],
        ['Mint', mint.address],
        ['ChaiDealer', chaiDealer.address],
        ['WethDealer', wethDealer.address],
      ]))
    };

    console.log(maturitiesOutput);
  }
};

/// @dev Returns the decimals in a number
/* function decimals(value) {
  if(Math.floor(value) === value) return 0;
  return value.toString().split(".")[1].length || 0; 
}; */

/// @dev Converts a number to RAY precision
/* function toRay(value) {
  return web3.utils.toBN(value.toString()) * web3.utils.toBN('10').pow(new BN(27).sub(new BN(decimals(value.toString())))); 
}; */

/// @dev Converts a number to RAY precision
/* function toRad(value) {
  return web3.utils.toBN(value.toString()) * web3.utils.toBN('10').pow((new BN(45)).sub(new BN(decimals(value.toString())))); 
}; */

/// @dev Converts a string to bytes32
/* function stringToBytes32(text) {
  let result = web3.utils.fromAscii(text);
  while (result.length < 66) result += '0'; // 0x + 64 digits
  return result;
}; */

/// @dev Converts a bytes32 to string
function bytes32ToString(text) {
  return web3.utils.toAscii(text).replace(/\0/g, '');
};