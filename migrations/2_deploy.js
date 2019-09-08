const Treasurer = artifacts.require("Treasurer");
const Token    = artifacts.require("yToken");

module.exports = function(deployer, network, accounts) {

  //if (network == "")
  //Token stands in for Dai
  deployer.deploy(Token, 0).then(function() {
      return deployer.deploy(Treasurer, accounts[0], Token.address, web3.utils.toWei("1.5"));
    });
};
