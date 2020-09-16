const Migrations = artifacts.require("Migrations");
const EDai = artifacts.require("EDai")
const ethers = require("ethers")
const fs = require('fs')

const CONTRACTS = [
    // MakerDao
    "Vat",
    "Weth",
    "WethJoin",
    "Dai",
    "DaiJoin",
    "Pot",
    "End",
    "Chai",

    // EDai
    "Treasury",
    "Controller",
    "Unwind",
    "Liquidations",
    "eDai0",
    "eDai1",
    "eDai2",
    "eDai3",
    "eDai4",
    "YieldProxy",
];

// Logs all addresses of contracts
module.exports = async (callback) => {
    try {
    const migrations = await Migrations.deployed();

    const network = await web3.eth.net.getId()

    data = {}

    for (const name of CONTRACTS) {
        // Get the contract from the registry
        const nameBytes = ethers.utils.formatBytes32String(name)
        const address = await migrations.contracts(nameBytes);
        data[name] = address;

        if (name.startsWith("eDai")) {
            const eDai = await EDai.at(address)
            const poolName = `${name}-Pool`
            const poolNameBytes = ethers.utils.formatBytes32String(poolName)
            const poolAddress = await migrations.contracts(poolNameBytes);
            data[poolName] = poolAddress;
        }
    }
    data["Migrations"] = migrations.address

    fs.writeFileSync(`./addrs_${network}.json`, JSON.stringify(data));
    callback()
    } catch (e) {console.log(e)}
}
