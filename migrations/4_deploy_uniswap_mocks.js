const UniswapFactoryMock = artifacts.require("UniswapFactoryMock");
const Treasurer = artifacts.require("Treasurer");
const Oracle = artifacts.require("Oracle");
const yToken = artifacts.require("yToken");

setup = async () => {
  let treasurer = await Treasurer.deployed();
  let oracle = await Oracle.deployed();
  var rate = web3.utils.toWei(".01");
  await oracle.set(rate);
  await treasurer.setOracle(oracle.address);
  var thedate = Math.floor(Date.now() / 1000) + (24*60*60)*30;
  await treasurer.issue(thedate.toString());
}

module.exports = function(deployer, network, accounts) {
  if(network == "development"){

    //var apromise = setup(deployer.provider);
    deployer.deploy(UniswapFactoryMock)
      .then(async () => {await setup()})

    //return apromise;
  }
};
