

Created using the following tutorial: https://medium.com/@ethdapp/build-smart-contracts-with-openzeppelin-and-truffle-67b2851d3b07




1.) Run truffle develop
2.) compile with `compile`, then `deploy`
3.)






Debug:

let t2 = await Treasurer.deployed()
let r2 = t2.mintMinerReward()
debug r2.tx



Treasurer.deployed().then(function(instance){return instance.mintMinerReward.call();}).then(function(value){return value.toNumber()});





`var y = await yToken.at(await t._a())`
var f = await y.totalSupply()
await y.approve(t.address, 1000)
await y.transfer(accounts[1], 1000)
Number(f.toString())
