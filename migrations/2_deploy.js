const Treasurer = artifacts.require("Treasurer");
const Token    = artifacts.require("yToken");
const MockContract = artifacts.require("./MockContract");

module.exports = function(deployer, network, accounts) {

  //if (network == "")
  //Token stands in for Dai
  deployer.deploy(MockContract);
  deployer.deploy(Token, 1)
    .then(function() {
        return deployer.deploy(Treasurer, accounts[0], Token.address, web3.utils.toWei("1.5"));
      });
};
