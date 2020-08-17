// Script used to audit the permissions of Yield Protocol
//
// Run as `node orchestration.js`. Requires having `ethers v5` installed.
// Provide arguments as environment variables:
// - ENDPOINT: The Ethereum node to connect to
// - MIGRATIONS: The address of the smart contract registry
// - START_BLOCK: The block to filter events from (default: 0). 
//   Do not set this to 0 if using with services like Infura
const ethers = require("ethers")

const ENDPOINT = process.env.ENDPOINT || "http://localhost:8545"
const MIGRATIONS = process.env.MIGRATIONS || "0xB8d5847ec245647CC11FA178C5d2377B85df328B" // defaults to the ganache deployment
const START_BLOCK = process.env.START_BLOCK || 0

// Human readable ABIs for Orchestrated contracts and for the registry
const ABI = [
    "event GrantedAccess(address user)",
    "function owner() view returns (address)",
    "function contracts(bytes32 name) view returns (address)",
];

const CONTRACTS = [
    "Treasury",
    "Controller",
    "Unwind",
    "Liquidations",
    "yDai0",
    "yDai1",
    "yDai2",
    "yDai3",
];

(async () => {
    const provider = new ethers.providers.JsonRpcProvider(ENDPOINT)
    const migrations = new ethers.Contract(MIGRATIONS, ABI, provider);

    const block = await provider.getBlockNumber()
    console.log(`Checking Yield Protocol permissions at block ${block}`)

    let data = {};
    data["Migrations"] = { "address" : MIGRATIONS }

    for (const name of CONTRACTS) {
        // Get the contract from the registry
        const nameBytes = ethers.utils.formatBytes32String(name)
        const address = await migrations.contracts(nameBytes);
        const contract = new ethers.Contract(address, ABI, provider);

        // Get the logs
        const logs = await contract.queryFilter("GrantedAccess", START_BLOCK)
        const privileged = logs.map(log => log.args.user)

        // save the data
        data[name] = {
            "address" : address,
            "owner" : await contract.owner(),
            "privileged": privileged,
        }
    }

    console.log(data)
})()
