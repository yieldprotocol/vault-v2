const { callbackify } = require('util');

const fs = require('fs')

const Migrations = artifacts.require("Migrations");

module.exports = function(deployer) {
  const branch = fs.readFileSync(".git/HEAD").toString().replace('ref: ','').trim() 
  const commit = fs.readFileSync(`.git/${branch}`).toString().trim()
  deployer.deploy(Migrations, commit);
};
