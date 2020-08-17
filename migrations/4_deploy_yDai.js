const fixed_addrs = require('./fixed_addrs.json');
const Migrations = artifacts.require("Migrations");
const Vat = artifacts.require("Vat");
const Pot = artifacts.require("Pot");
const Treasury = artifacts.require("Treasury");
const YDai = artifacts.require("YDai");
const Controller = artifacts.require("Controller");
const Unwind = artifacts.require("Unwind");

module.exports = async (deployer, network, accounts) => {
  const migrations = await Migrations.deployed();

  let vatAddress;
  let potAddress;
  let treasuryAddress;
  let controllerAddress;
  let unwindAddress;

  if (network !== 'development') {
    vatAddress = fixed_addrs[network].vatAddress;
    potAddress = fixed_addrs[network].potAddress;
  } else {
    vatAddress = (await Vat.deployed()).address;
    potAddress = (await Pot.deployed()).address;
  }

  const treasury = await Treasury.deployed();
  treasuryAddress = treasury.address;
  const controller = await Controller.deployed();
  controllerAddress = controller.address;
  const unwind = await Unwind.deployed();
  unwindAddress = unwind.address;
  
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
      vatAddress,
      potAddress,
      treasuryAddress,
      maturity,
      name,
      symbol,
    );
    const yDai = await YDai.deployed();
    await treasury.orchestrate(yDai.address);
    await controller.addSeries(yDai.address);
    await yDai.orchestrate(controllerAddress);
    await yDai.orchestrate(unwindAddress);

    await migrations.register(web3.utils.fromAscii('yDai' + index), yDai.address);
    console.log('yDai' + index, yDai.address);
    index++;
  }
};