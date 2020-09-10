const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const ERC20 = artifacts.require("TestDai");
const EDai = artifacts.require("EDai");
const Pool = artifacts.require("Pool");
const YieldMath = artifacts.require("YieldMath.sol");

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();

  let daiAddress;
  let eDaiAddress;

  const eDaiNames = ['eDai0', 'eDai1', 'eDai2', 'eDai3'];

  if (network !== 'development') {
    daiAddress = fixed_addrs[network].daiAddress;
  } else {
    daiAddress = (await ERC20.deployed()).address;
  }

  // Deploy and link YieldMath
  await deployer.deploy(YieldMath)
  await deployer.link(YieldMath, Pool);  

  for (eDaiName of eDaiNames) {
    eDaiAddress = await migrations.contracts(web3.utils.fromAscii(eDaiName));
    eDai = await EDai.at(eDaiAddress);

    await deployer.deploy(
      Pool,
      daiAddress,
      eDaiAddress,
      (await eDai.name()) + '-Pool',
      (await eDai.symbol()) + '-Pool',
    );
    pool = await Pool.deployed();
    await migrations.register(web3.utils.fromAscii((await eDai.name()) + '-Pool'), pool.address);
    console.log((await eDai.name()) + '-Pool', pool.address);
  }
};
