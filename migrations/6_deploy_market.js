const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const Pot = artifacts.require("Pot");
const Chai = artifacts.require("Chai");
const YDai = artifacts.require("YDai");
const Market = artifacts.require("Market");
const LimitMarket = artifacts.require("LimitMarket");
const YieldMath = artifacts.require("YieldMath.sol");

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();

  let potAddress;
  let chaiAddress;
  let yDaiAddress;
  let marketAddress;

  if (network !== 'development') {
    potAddress = fixed_addrs[network].potAddress;
    fixed_addrs[network].chaiAddress ? 
      (chaiAddress = fixed_addrs[network].chaiAddress)
      : (chaiAddress = (await Chai.deployed()).address);
  } else {
      potAddress = (await Pot.deployed()).address;
      chaiAddress = (await Chai.deployed()).address;
  }

  // Deploy and link YieldMath - TODO: Is this needed?
  await deployer.deploy(YieldMath)
  await deployer.link(YieldMath, Market);  

  let yDaiNames = ['yDai1', 'yDai2', 'yDai3', 'yDai4']; // TODO: Consider iterating until the address returned is 0
  for (yDaiName of yDaiNames) {
    yDaiAddress = migrations.contracts(web3.utils.fromAscii(yDaiName));
    // TODO: Fix out of gas
    await deployer.deploy(
      Market,
      potAddress,
      chaiAddress,
      yDaiAddress,
    );
    market = await Market.deployed();
    await migrations.register(web3.utils.fromAscii('Market-' + yDaiName), market.address);
    console.log('Market-' + yDaiName, market.address);

    await deployer.deploy(
      LimitMarket,
      chaiAddress,
      yDaiAddress,
      market.address,
    );
    limitMarket = await LimitMarket.deployed();
    await migrations.register(web3.utils.fromAscii('LimitMarket-' + yDaiName), limitMarket.address);
    console.log('LimitMarket-' + yDaiName, limitMarket.address);
  }
};