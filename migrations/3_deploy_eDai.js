const fixed_addrs = require('./fixed_addrs.json');

const Migrations = artifacts.require("Migrations");

const Vat = artifacts.require("Vat");
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("Dai");
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

  const toDate = (timestamp) => (new Date(timestamp * 1000)).toISOString().slice(0,10)
  const toTimestamp = (date) => (new Date(date)).getTime() / 1000
  const toSymbol = (date) => 
    new Intl.DateTimeFormat('en', { year: 'numeric' }).format(new Date(date)).slice(2) +
    new Intl.DateTimeFormat('en', { month: 'short' }).format(new Date(date))


  let dates = [
    '2020-10-01',
    '2021-01-01',
    '2021-04-01',
    '2021-07-01',
  ]

  if (network === "mainnet") {
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

    const block = await web3.eth.getBlockNumber()
    const maturity = (await web3.eth.getBlock(block)).timestamp + 3600
    dates.push(toDate(maturity));
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

  const deployedEDais = {}

  for (i in dates) {
    eDaiMaturity = toTimestamp(dates[i])
    eDaiName = `Yield Dai - ${dates[i]}`
    eDaiSymbol = `eDai${toSymbol(dates[i])}`

    // Setup EDai
    await deployer.deploy(
      EDai,
      treasuryAddress,
      eDaiMaturity,
      eDaiName,
      eDaiSymbol,
    );
    const eDai = await EDai.deployed()
    deployedEDais[eDaiSymbol] = eDai.address
  }
  for (name in deployedEDais) {
    await migrations.register(web3.utils.fromAscii(name), deployedEDais[name]);
  }
  console.log(deployedEDais);
};
