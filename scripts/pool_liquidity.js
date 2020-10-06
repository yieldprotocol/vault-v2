// npx truffle exec --network [network] scripts/pool_liquidity.js --migrations [migrations contract address]
// If a network is not provided, it will check in the development one
// If a migrations address is not provided, it will look for the latest deployed instance

const Migrations = artifacts.require('Migrations')
const Pool = artifacts.require('Pool')

module.exports = async (deployer, network) => {
  let migrations
  if (process.argv.indexOf('--migrations') > -1)
    migrations = await Migrations.at(process.argv[process.argv.indexOf('--migrations') + 1])
  else 
    migrations = await Migrations.deployed()
  
  const contracts = await migrations.length()
  for (let i = 0; i < contracts; i++) {
    const contractName = web3.utils.toAscii(await migrations.names(i))

    if (contractName.includes('fyDaiLP')) {
      const pool = await Pool.at(await migrations.contracts(web3.utils.fromAscii(contractName)))
      console.log(contractName)
      console.log(`Dai Reserves:   ${await pool.getDaiReserves()}`)
      console.log(`FYDai Reserves: ${await pool.getFYDaiReserves()}`)
      console.log()
    }
  }
  console.log("Press Ctrl+C to exit")
}
