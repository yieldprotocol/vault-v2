const UniswapFactoryMock = artifacts.require("UniswapFactoryMock");

module.exports = function(deployer, network, accounts) {
  if(network == "development")
    deployer.deploy(UniswapFactoryMock);
};
