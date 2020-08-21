const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const ERC20 = artifacts.require("TestERC20");
const YDai = artifacts.require("YDai");
const Pool = artifacts.require("Pool");
const YieldMath = artifacts.require("YieldMath.sol");

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();

  let daiAddress;
  let yDaiAddress;
  let poolAddress;

  const yDaiNames = ['yDai0', 'yDai1', 'yDai2', 'yDai3'];

  if (network !== 'development') {
    daiAddress = fixed_addrs[network].daiAddress;
  } else {
    daiAddress = (await ERC20.deployed()).address;
  }

  // Deploy and link YieldMath
  await deployer.deploy(YieldMath)
  await deployer.link(YieldMath, Pool);  

  for (yDaiName of yDaiNames) {
    yDaiAddress = await migrations.contracts(web3.utils.fromAscii(yDaiName));
    yDai = await YDai.at(yDaiAddress);

    await deployer.deploy(
      Pool,
      daiAddress,
      yDaiAddress,
      (await yDai.name()) + '-Pool',
      (await yDai.symbol()) + '-Pool',
    );
    pool = await Pool.deployed();
    await migrations.register(web3.utils.fromAscii((await yDai.name()) + '-Pool'), pool.address);
    console.log((await yDai.name()) + '-Pool', pool.address);
  }
};