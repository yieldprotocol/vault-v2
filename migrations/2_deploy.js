// const { BN } = require('@openzeppelin/test-helpers');

module.exports = async (deployer, network, accounts) => {
  const [ owner ] = accounts;
  console.log("Owner: " + owner);

  let vat;
  let weth;
  let wethJoin;
  let dai;
  let daiJoin;
  let pot;
  let chai;
  let treasury;
  let chaiOracle;
  let wethOracle;

  if (network == "development") {
    // Setting up Vat
    const ERC20 = artifacts.require("TestERC20");
    const Vat = artifacts.require("Vat");
    const GemJoin = artifacts.require("GemJoin");
    const DaiJoin = artifacts.require("DaiJoin");
    const Pot = artifacts.require("Pot");
    const Chai = artifacts.require("Chai");

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
  };

  if (network == "mainnet") {
    vat = "0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B";
    weth = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
    wethJoin = "0x2F0b23f53734252Bda2277357e97e1517d6B042A";
    dai = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
    daiJoin = "0x9759A6Ac90977b93B58547b4A71c78317f391A28";
    pot = "0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7";
    chai = "0x06af07097c9eeb7fd685c692751d5c66db49c215";
  };

  if (network == "kovan") {
    vat = "0xbA987bDB501d131f766fEe8180Da5d81b34b69d9";
    weth = "0xd0A1E359811322d97991E03f863a0C30C2cF029C";
    wethJoin = "0x775787933e92b709f2a3C70aa87999696e74A9F8";
    dai = "0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa";
    daiJoin = "0x5AA71a3ae1C0bd6ac27A1f28e1415fFFB6F15B8c";
    pot = "0xEA190DBDC7adF265260ec4dA6e9675Fd4f5A78bb";
    chai = "0x";
  };

  if (network == "goerli") {
    vat = "0x0de72A41138079f8052e4625C24eD06ac55c97Be";
    weth = "0x222CB0e85cDD0dc66bB79587399DE1d4eD9Ed6D9";
    wethJoin = "0xf5d1Af9424CF64F23f713817CCf38F3F0F7bd716";
    dai = "0x7D750374481D8E3190aB39cAFf94f3aB28502f5D";
    daiJoin = "0xB62FFaBf09E23bd6082dd1491bFb5511BD518d23";
    pot = "0x9C42a352B2814E6b103E9ba91da7922b76C86924";
    chai = "0x";
  };

  if (network == "rinkeby") {
    vat = "0x6E631D87bF9456495dDC9bDa576534592f486964";
    weth = "0xc421f99D871aC5793985fd86d8659B7bDACFc9AC";
    wethJoin = "0xA6268caddf03356aF17C7259E10d865C9DF48863";
    dai = "0x6A9865aDE2B6207dAAC49f8bCba9705dEB0B0e6D";
    daiJoin = "0xa956A2a53C3F8F3Dc02793F7b13e8121aD114c54";
    pot = "0x867E3054af4d30fCCF0fCf3B6e855B49EF7e02Ed";
    chai = "0x";
  };

  if (network == "ropsten") {
    vat = "0xFfCFcAA53b61cF5F332b4FBe14033c1Ff5A391eb";
    weth = "0x7715c353d352Ac5746A063AFe2036A092b5D0db0";
    wethJoin = "0xa885b27E8754f8238DBedaBd2eae180490C341d7";
    dai = "0x31F42841c2db5173425b5223809CF3A38FEde360";
    daiJoin = "0xA0b569e9E0816A20Ab548D692340cC28aC7Be986";
    pot = "0x9588a660241aeA569B3965e2f00631f2C5eDaE33";
    chai = "0x";
  };

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
    ]));

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