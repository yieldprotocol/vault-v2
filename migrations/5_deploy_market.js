const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const ERC20 = artifacts.require("TestERC20");
const YDai = artifacts.require("YDai");
const Market = artifacts.require("Market");
const LimitMarket = artifacts.require("LimitMarket");
const YieldMath = artifacts.require("YieldMath.sol");

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();

  let daiAddress;
  let yDaiAddress;
  let marketAddress;

  const yDaiNames = ['yDai0', 'yDai1', 'yDai2', 'yDai3']; // TODO: Consider iterating until the address returned is 0

  if (network !== 'development') {
    daiAddress = fixed_addrs[network].daiAddress;
  } else {
    daiAddress = (await ERC20.deployed()).address;
  }

  // Deploy and link YieldMath - TODO: Is this needed?
  await deployer.deploy(YieldMath)
  await deployer.link(YieldMath, Market);  

  for (yDaiName of yDaiNames) {
    yDaiAddress = await migrations.contracts(web3.utils.fromAscii(yDaiName));
    yDai = await YDai.at(yDaiAddress);

    await deployer.deploy(
      Market,
      daiAddress,
      yDaiAddress,
      (await yDai.name()) + '-Pool',
      (await yDai.symbol()) + '-Pool',
    );
    market = await Market.deployed();
    await migrations.register(web3.utils.fromAscii((await yDai.name()) + '-Pool'), market.address);
    console.log((await yDai.name()) + '-Pool', market.address);

    await deployer.deploy(
      LimitMarket,
      daiAddress,
      yDaiAddress,
      market.address,
    );
    limitMarket = await LimitMarket.deployed();
    await migrations.register(web3.utils.fromAscii((await yDai.name()) + '-Limit'), limitMarket.address);
    console.log((await yDai.name()) + '-Limit', limitMarket.address);
  }
};