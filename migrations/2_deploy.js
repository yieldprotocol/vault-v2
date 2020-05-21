// const { BN } = require('@openzeppelin/test-helpers');

module.exports = async (deployer, network, accounts) => {
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

  if (network === "development") {
    // Setting up Vat
    const ERC20 = artifacts.require("TestERC20");
    const Vat = artifacts.require("Vat");
    const GemJoin = artifacts.require("GemJoin");
    const DaiJoin = artifacts.require("DaiJoin");
    const Pot = artifacts.require("Pot");

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
    const vat = await Vat.deployed();
    vatAddress = vat.address;
    await vat.rely(vatAddress);
    await vat.init(ilk); // Set ilk rate to 1.0

    await deployer.deploy(ERC20, 0);
    wethAddress = (await ERC20.deployed()).address;

    await deployer.deploy(GemJoin, vatAddress, ilk, wethAddress);
    wethJoinAddress = (await GemJoin.deployed()).address;

    await deployer.deploy(ERC20, 0);
    daiAddress = (await ERC20.deployed()).address;

    await deployer.deploy(DaiJoin, vatAddress, daiAddress);
    daiJoinAddress = (await DaiJoin.deployed()).address;
    await vat.rely(daiJoinAddress);

    // Setup spot and limits
    await vat.file(ilk, spotName, spot);
    await vat.file(ilk, linel, limits);
    await vat.file(Line, limits);

    // Setup Pot
    await deployer.deploy(Pot, vatAddress);
    potAddress = (await Pot.deployed()).address;
    await vat.rely(potAddress);
  };

  if (network === "mainnet") {
    vatAddress = "0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B";
    wethAddress = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
    wethJoinAddress = "0x2F0b23f53734252Bda2277357e97e1517d6B042A";
    daiAddress = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
    daiJoinAddress = "0x9759A6Ac90977b93B58547b4A71c78317f391A28";
    potAddress = "0x197E90f9FAD81970bA7976f33CbD77088E5D7cf7";
    chaiAddress = "0x06af07097c9eeb7fd685c692751d5c66db49c215";
  };

  if (network === "kovan" || network === "kovan-fork") {
    vatAddress = "0xbA987bDB501d131f766fEe8180Da5d81b34b69d9";
    wethAddress = "0xd0A1E359811322d97991E03f863a0C30C2cF029C";
    wethJoinAddress = "0x775787933e92b709f2a3C70aa87999696e74A9F8";
    daiAddress = "0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa";
    daiJoinAddress = "0x5AA71a3ae1C0bd6ac27A1f28e1415fFFB6F15B8c";
    potAddress = "0xEA190DBDC7adF265260ec4dA6e9675Fd4f5A78bb";
    chaiAddress = "0xb641957b6c29310926110848db2d464c8c3c3f38";
  };

  if (network === "goerli" || network === "goerli-fork") {
    vatAddress = "0x0de72A41138079f8052e4625C24eD06ac55c97Be";
    wethAddress = "0x222CB0e85cDD0dc66bB79587399DE1d4eD9Ed6D9";
    wethJoinAddress = "0xf5d1Af9424CF64F23f713817CCf38F3F0F7bd716";
    daiAddress = "0x7D750374481D8E3190aB39cAFf94f3aB28502f5D";
    daiJoinAddress = "0xB62FFaBf09E23bd6082dd1491bFb5511BD518d23";
    potAddress = "0x9C42a352B2814E6b103E9ba91da7922b76C86924";
  };    

  if (network === "rinkeby" || network === "rinkeby-fork") {
    vatAddress = "0x6E631D87bF9456495dDC9bDa576534592f486964";
    wethAddress = "0xc421f99D871aC5793985fd86d8659B7bDACFc9AC";
    wethJoinAddress = "0xA6268caddf03356aF17C7259E10d865C9DF48863";
    daiAddress = "0x6A9865aDE2B6207dAAC49f8bCba9705dEB0B0e6D";
    daiJoinAddress = "0xa956A2a53C3F8F3Dc02793F7b13e8121aD114c54";
    potAddress = "0x867E3054af4d30fCCF0fCf3B6e855B49EF7e02Ed";
  };

  if (network === "ropsten" || network === "ropsten-fork") {
    vatAddress = "0xFfCFcAA53b61cF5F332b4FBe14033c1Ff5A391eb";
    wethAddress = "0x7715c353d352Ac5746A063AFe2036A092b5D0db0";
    wethJoinAddress = "0xa885b27E8754f8238DBedaBd2eae180490C341d7";
    daiAddress = "0x31F42841c2db5173425b5223809CF3A38FEde360";
    daiJoinAddress = "0xA0b569e9E0816A20Ab548D692340cC28aC7Be986";
    potAddress = "0x9588a660241aeA569B3965e2f00631f2C5eDaE33";
  };

  if (network !== "mainnet" && network !== "kovan" && network !== "kovan-fork") {
    const Chai = artifacts.require("Chai");

    // Setup Chai
    await deployer.deploy(
      Chai,
      vatAddress,
      potAddress,
      daiJoinAddress,
      daiAddress,
    );
    chaiAddress = (await Chai.deployed()).address;
    // TODO: Make this work in goerli, ropsten and rinkeby
    const Vat = artifacts.require("Vat");
    const vat = Vat.at(vatAddress);
    await vat.rely(chaiAddress);
  };

  // --- TODO: Find out how to move the next section to 3_deploy, passing the addresses on
  
  console.log("    External contract addresses");
  console.log("    ---------------------------");
  console.log("    vat:      " + vatAddress);
  console.log("    weth:     " + wethAddress);
  console.log("    wethJoin: " + wethJoinAddress);
  console.log("    dai:      " + daiAddress);
  console.log("    daiJoin:  " + daiJoinAddress);
  console.log("    chai:     " + chaiAddress);

  const Treasury = artifacts.require("Treasury");
  const ChaiOracle = artifacts.require("ChaiOracle");
  const WethOracle = artifacts.require("WethOracle");

  await deployer.deploy(
    Treasury,
    daiAddress,        // dai
    chaiAddress,       // chai
    wethAddress,       // weth
    daiJoinAddress,    // daiJoin
    wethJoinAddress,   // wethJoin
    vatAddress,        // vat
  );
  treasury = await Treasury.deployed();
  treasuryAddress = treasury.address;

  // Setup chaiOracle
  await deployer.deploy(ChaiOracle, potAddress);
  chaiOracleAddress = (await ChaiOracle.deployed()).address;

  // Setup wethOracle
  await deployer.deploy(WethOracle, vatAddress);
  wethOracleAddress = (await WethOracle.deployed()).address;

  // --- TODO: Find out how to move the next section to 4_deploy, passing the addresses on

  // Setup yDai - TODO: Replace by the right maturities, there will be several of these
  const YDai = artifacts.require("YDai");
  const Mint = artifacts.require("Mint");
  const ChaiDealer = artifacts.require("ChaiDealer");
  const WethDealer = artifacts.require("WethDealer");

  // const block = await web3.eth.getBlockNumber();
  const maturitiesInput = new Set([
    // [(await web3.eth.getBlock(block)).timestamp + 1000, 'Name1','Symbol1'],
    // [(await web3.eth.getBlock(block)).timestamp + 2000, 'Name2','Symbol2'],
    // [(await web3.eth.getBlock(block)).timestamp + 3000, 'Name3','Symbol3'],
    // [(await web3.eth.getBlock(block)).timestamp + 4000, 'Name4','Symbol4'],
    [1601510399, 'yDai-2020-09-30', 'yDai-2020-09-30'],
    [1609459199, 'yDai-2020-12-31', 'yDai-2020-12-31'],
    [1617235199, 'yDai-2021-03-31', 'yDai-2021-03-31'],
    [1625097599, 'yDai-2021-06-30', 'yDai-2021-06-30'],
  ]);

  const maturitiesOutput = [];
  for (const [maturity, name, symbol] of maturitiesInput.values()) {
    // Setup YDai
    await deployer.deploy(
      YDai,
      vatAddress,
      potAddress,
      maturity,
      name,
      symbol,
      { gas: 5000000 },
    );
    const yDai = await YDai.deployed();
    const yDaiAddress = yDai.address;

    // Setup mint
    await deployer.deploy(
      Mint,
      treasuryAddress,
      daiAddress,
      yDaiAddress,
      { gas: 5000000 },
    );
    const mint = await Mint.deployed();
    await yDai.grantAccess(mint.address);
    await treasury.grantAccess(mint.address);

    // Setup ChaiDealer
    await deployer.deploy(
      ChaiDealer,
      treasuryAddress,
      daiAddress,
      yDaiAddress,
      chaiAddress,
      chaiOracleAddress,
      { gas: 5000000 },
    );
    const chaiDealer = await ChaiDealer.deployed();
    await yDai.grantAccess(chaiDealer.address);
    await treasury.grantAccess(chaiDealer.address);
  
    // Setup WethDealer
    await deployer.deploy(
      WethDealer,
      treasuryAddress,
      daiAddress,
      yDaiAddress,
      wethAddress,
      wethOracleAddress,
      { gas: 5000000 },
    );
    const wethDealer = await WethDealer.deployed();
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
/* function bytes32ToString(text) {
  return web3.utils.toAscii(text).replace(/\0/g, '');
}; */