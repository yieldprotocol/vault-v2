const fixed_addrs = require('./fixed_addrs.json');

const Migrations = artifacts.require("Migrations");

const Vat = artifacts.require("Vat");
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
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
  
  const maturitiesInput = new Set([
    [1601510399, 'yDai-2020-09-30', 'yDai-2020-09-30'],
    [1609459199, 'yDai-2020-12-31', 'yDai-2020-12-31'],
    [1617235199, 'yDai-2021-03-31', 'yDai-2021-03-31'],
    [1625097599, 'yDai-2021-06-30', 'yDai-2021-06-30'],
  ]);

  if (network === 'development') {
    const block = await web3.eth.getBlockNumber();
    maturitiesInput.add(
      [(await web3.eth.getBlock(block)).timestamp + 100, 'yDai-t0', 'yDai-t0'],
    );
  }

  let index = 0;
  for (const [maturity, name, symbol] of maturitiesInput.values()) {
    // Setup YDai
    await deployer.deploy(
      YDai,
      treasuryAddress,
      maturity,
      name,
      symbol,
    );
    const yDai = await YDai.deployed()

    await migrations.register(web3.utils.fromAscii('yDai' + index), yDai.address);
    console.log('yDai' + index, yDai.address);
    index++;
  }
};
