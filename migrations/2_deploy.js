const Treasurer = artifacts.require("Treasurer");
const Token    = artifacts.require("yToken");
const MockContract = artifacts.require("./MockContract");

module.exports = function(deployer, network, accounts) {

  //if (network == "")
  //Token stands in for Dai
  deployer.deploy(MockContract);
  deployer.deploy(
          Treasurer,
          accounts[0],
          web3.utils.toWei("1.5"),
          web3.utils.toWei("1.05")
  );

};
