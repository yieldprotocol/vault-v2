// const { BN } = require('@openzeppelin/test-helpers');
const fixed_addrs = require('./fixed_addrs.json');
const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const End = artifacts.require('End');
const Chai = artifacts.require('Chai');
const GasToken = artifacts.require('GasToken1');
const Migrations = artifacts.require("Migrations");

const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../test/shared/utils');

module.exports = async (deployer, network, accounts) => {
  const [owner] = accounts;
  let vatAddress;
  let wethAddress;
  let wethJoinAddress;
  let daiAddress;
  let daiJoinAddress;
  let potAddress;
  let endAddress;
  let chaiAddress;
  let gasTokenAddress;

  if (network === "development") {
    // Setting up Vat
    const ilk = web3.utils.fromAscii("ETH-A");
    const Line = web3.utils.fromAscii("Line");
    const spotName = web3.utils.fromAscii("spot");
    const linel = web3.utils.fromAscii("line");

    const limits = toRad(10000);
    const spot  = toRay(1.5);
    const rate  = toRay(1.25);
    const chi = toRay(1.2);

    // Setup vat
    await deployer.deploy(Vat);
    const vat = await Vat.deployed();
    vatAddress = vat.address;
    await vat.init(ilk);
    await vat.file(ilk, spotName, spot);
    await vat.file(ilk, linel, limits);
    await vat.file(Line, limits);
    await vat.fold(ilk, vatAddress, subBN(rate, toRay(1)));

    await deployer.deploy(Weth);
    wethAddress = (await Weth.deployed()).address;

    await deployer.deploy(GemJoin, vatAddress, ilk, wethAddress);
    wethJoinAddress = (await GemJoin.deployed()).address;

    await deployer.deploy(ERC20, 0);
    daiAddress = (await ERC20.deployed()).address;

    await deployer.deploy(DaiJoin, vatAddress, daiAddress);
    daiJoinAddress = (await DaiJoin.deployed()).address;

    // Setup pot
    await deployer.deploy(Pot, vatAddress);
    const pot = await Pot.deployed();
    potAddress = pot.address;
    await pot.setChi(chi);

    // Setup end
    await deployer.deploy(End)
    const end = await End.deployed();
    endAddress = end.address;
    await end.file(web3.utils.fromAscii("vat"), vatAddress);

    // Permissions
    await vat.rely(vatAddress);
    await vat.rely(wethJoinAddress);
    await vat.rely(daiJoinAddress);
    await vat.rely(potAddress);
    await vat.rely(endAddress);

  };

  if (network !== 'development') {
    vatAddress = fixed_addrs[network].vatAddress ;
    wethAddress = fixed_addrs[network].wethAddress;
    wethJoinAddress = fixed_addrs[network].wethJoinAddress;
    daiAddress = fixed_addrs[network].daiAddress;
    daiJoinAddress = fixed_addrs[network].daiJoinAddress;
    potAddress = fixed_addrs[network].potAddress;
    endAddress = fixed_addrs[network].endAddress;
    fixed_addrs[network].chaiAddress && (chaiAddress = fixed_addrs[network].chaiAddress);
  };

  if (network === "development" || network === "goerli" && network === "goerli-fork") {
    // Setup Chai
    await deployer.deploy(GasToken);
    gasTokenAddress = (await GasToken.deployed()).address;
  };

  if (network !== "mainnet" && network !== "kovan" && network !== "kovan-fork") {
    // Setup Chai
    await deployer.deploy(
      Chai,
      vatAddress,
      potAddress,
      daiJoinAddress,
      daiAddress,
    );
    chaiAddress = (await Chai.deployed()).address;
  };
  
  console.log("    External contract addresses");
  console.log("    ---------------------------");
  console.log("    vat:      " + vatAddress);
  console.log("    weth:     " + wethAddress);
  console.log("    wethJoin: " + wethJoinAddress);
  console.log("    dai:      " + daiAddress);
  console.log("    daiJoin:  " + daiJoinAddress);
  console.log("    chai:     " + chaiAddress);
  console.log("    gasToken: " + gasTokenAddress);
}