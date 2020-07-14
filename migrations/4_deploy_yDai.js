const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const Vat = artifacts.require("Vat");
const Jug = artifacts.require("Jug");
const Pot = artifacts.require("Pot");
const Treasury = artifacts.require("Treasury");
const Controller = artifacts.require("Controller");
const YDai = artifacts.require("YDai");

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();

  let vatAddress;
  let jugAddress;
  let potAddress;
  let treasuryAddress;
  let controllerAddress;

  if (network !== 'development') {
    vatAddress = fixed_addrs[network].vatAddress;
    jugAddress = fixed_addrs[network].jugAddress;
    potAddress = fixed_addrs[network].potAddress;
  } else {
    vatAddress = (await Vat.deployed()).address;
    jugAddress = (await Jug.deployed()).address;
    potAddress = (await Pot.deployed()).address;
  }

  const treasury = await Treasury.deployed();
  treasuryAddress = treasury.address;
  const controller = await Controller.deployed();
  controllerAddress = controller.address;
  
  // const block = await web3.eth.getBlockNumber();
  const maturitiesInput = new Set([
    // [(await web3.eth.getBlock(block)).timestamp + 1000, 'Name1','Symbol1'],
    [1601510399, 'yDai-2020-09-30', 'yDai-2020-09-30'],
    [1609459199, 'yDai-2020-12-31', 'yDai-2020-12-31'],
    [1617235199, 'yDai-2021-03-31', 'yDai-2021-03-31'],
    [1625097599, 'yDai-2021-06-30', 'yDai-2021-06-30'],
  ]);

  if (network === 'development') {
    maturitiesInput.add(
      [1, 'yDai-t0', 'yDai-t0'],
    );
  }

  let index = 0;
  for (const [maturity, name, symbol] of maturitiesInput.values()) {
    // Setup YDai
    await deployer.deploy(
      YDai,
      vatAddress,
      jugAddress,
      potAddress,
      treasuryAddress,
      maturity,
      name,
      symbol,
    );
    const yDai = await YDai.deployed();
    await treasury.orchestrate(yDai.address);
    await yDai.orchestrate(controllerAddress);
    await controller.addSeries(yDai.address);

    await migrations.register(web3.utils.fromAscii('yDai' + index), yDai.address);
    console.log('yDai' + index, yDai.address);
    index++;
  }
};