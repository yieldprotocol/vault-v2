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
const EDai = artifacts.require("EDai");

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

  if (network !== 'development' && network !== 'rinkeby' && network !== 'rinkeby-fork' && network !== 'kovan' && network !== 'kovan-fork') {
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
  const toSymbol = (date) => 
    new Intl.DateTimeFormat('en', { year: 'numeric' }).format(new Date(date)).slice(2) + '-' +
    new Intl.DateTimeFormat('en', { month: 'short' }).format(new Date(date))


  let dates;
  if (network !== 'mainnet') {
      dates = [
          '2020-09-15',
          '2021-10-01',
          '2021-01-01',
          '2021-12-31',
      ]
  } else {
      dates = [
          '2020-10-01',
          '2021-01-01',
          '2021-04-01',
          '2021-07-01',
      ]
  }
  let maturities = dates.map(toTimestamp)
  let symbols = dates.map(toSymbol)

  if (network === 'development') {
    const block = await web3.eth.getBlockNumber()
    const maturity = (await web3.eth.getBlock(block)).timestamp + 1000
    maturities.push(maturity);
    symbols.push(toSymbol(new Date().toISOString().slice(0,10)));
  }

  let index = 0;
  for (const i in maturities) {
    // Setup EDai
    await deployer.deploy(
      EDai,
      treasuryAddress,
      maturities[i],
      `Yield Dai - ${dates[i]}`,
      `eDai-${symbols[i]}`,
    );
    const eDai = await EDai.deployed()

    await migrations.register(web3.utils.fromAscii('eDai' + index), eDai.address);
    console.log('eDai' + index, eDai.address);
    index++;
  }
};
