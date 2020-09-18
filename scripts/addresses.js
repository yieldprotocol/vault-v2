const Migrations = artifacts.require('Migrations')
const ethers = require('ethers')
const fs = require('fs')

// Logs all addresses of contracts
module.exports = async (callback) => {
  try {
    const migrations = await Migrations.deployed()

    const network = await web3.eth.net.getId()

    data = {}
    data['Version'] = await migrations.version()

    for (let i = 0; i < (await migrations.length()); i++) {
      const name = await migrations.names(i)
      data[ethers.utils.parseBytes32String(name)] = await migrations.contracts(name)
    }
    data['Migrations'] = migrations.address

    fs.writeFileSync(`./addrs_${network}.json`, JSON.stringify(data))
    callback()
  } catch (e) {
    console.log(e)
  }
}
