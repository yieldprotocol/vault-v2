const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const Dai = artifacts.require("Dai");
const EDai = artifacts.require("EDai");
const Pool = artifacts.require("Pool");
const YieldMath = artifacts.require("YieldMath.sol");

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();

  let daiAddress;
  let eDaiAddress;

  let numEDais = network !== 'mainnet' ? 5 : 4
  let eDaiNames = await Promise.all([...Array(numEDais).keys()].map(async (index) => {
      return 'eDai' + index
  }))

  if (network === "mainnet") {
    daiAddress = fixed_addrs[network].daiAddress;
  } else {
    daiAddress = (await Dai.deployed()).address;
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
      (await eDai.symbol()).replace('eDai','eDaiLP'),
    );
    pool = await Pool.deployed();
    await migrations.register(web3.utils.fromAscii(`${eDaiName}-Pool`), pool.address);
    console.log(`${eDaiName}-Pool`, pool.address);
  }
};
