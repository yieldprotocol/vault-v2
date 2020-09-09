const fixed_addrs = require('./fixed_addrs.json');

const Migrations = artifacts.require("Migrations");

const Vat = artifacts.require("Vat");
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestDai");
const GemJoin = artifacts.require("GemJoin");
const DaiJoin = artifacts.require("DaiJoin");
const Pot = artifacts.require("Pot");
const Chai = artifacts.require("Chai");

const Treasury = artifacts.require("Treasury");
const YDai = artifacts.require("YDai");

module.exports = async (deployer, network) => {
  const migrations = await Migrations.deployed();

  let vatAddress;
  let wethAddress;
  let wethJoinAddress;
  let daiAddress;
  let daiJoinAddress;
  let potAddress;
  let chaiAddress;
  let treasuryAddress;

  if (network !== 'development') {
    vatAddress = fixed_addrs[network].vatAddress ;
    wethAddress = fixed_addrs[network].wethAddress;
    wethJoinAddress = fixed_addrs[network].wethJoinAddress;
    daiAddress = fixed_addrs[network].daiAddress;
    daiJoinAddress = fixed_addrs[network].daiJoinAddress;
    potAddress = fixed_addrs[network].potAddress;
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
    chaiAddress = (await Chai.deployed()).address;
 }

  // Setup treasury
  await deployer.deploy(
    Treasury,
    vatAddress,
    wethAddress,
    daiAddress,
    wethJoinAddress,
    daiJoinAddress,
    potAddress,
    chaiAddress,
  );

  const treasury = await Treasury.deployed();
  treasuryAddress = treasury.address;
    
  const toTimestamp = (date) => (new Date(date)).getTime() / 1000
  const dates = [
        '2020-10-01',
        '2021-01-01',
        '2021-04-01',
        '2021-07-01',
  ]
  let maturities = dates.map(toTimestamp)

  if (network === 'development') {
    const block = await web3.eth.getBlockNumber();
    maturities.push(
      (await web3.eth.getBlock(block)).timestamp + 100,
    );
  }

  let index = 0;
  for (const i in maturities) {
    // Setup YDai
    await deployer.deploy(
      YDai,
      treasuryAddress,
      maturities[i],
      `Yield Dai - ${dates[i]}`,
      `yDAI-${dates[i]}`,
    );
    const yDai = await YDai.deployed()

    await migrations.register(web3.utils.fromAscii('yDai' + index), yDai.address);
    console.log('yDai' + index, yDai.address);
    index++;
  }
};
