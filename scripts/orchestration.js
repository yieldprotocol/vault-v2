// Script used to audit the permissions of Yield Protocol
//
// Run as `node orchestration.js`. Requires having `ethers v5` installed.
// Provide arguments as environment variables:
// - ENDPOINT: The Ethereum node to connect to
// - MIGRATIONS: The address of the smart contract registry
// - START_BLOCK: The block to filter events from (default: 0).
//   Do not set this to 0 if using with services like Infura
const ethers = require('ethers')

const ENDPOINT = process.env.ENDPOINT || 'http://localhost:8545'
const MIGRATIONS = process.env.MIGRATIONS || '0xb8d5847ec245647cc11fa178c5d2377b85df328b' // defaults to the ganache deployment
const START_BLOCK = process.env.START_BLOCK || 0

// Human readable ABIs for Orchestrated contracts and for the registry
const ABI = [
  'event GrantedAccess(address access, bytes4 signature)',
  'function owner() view returns (address)',
  'function contracts(bytes32 name) view returns (address)',
]

const CONTRACTS = [
  'Treasury',
  'Controller',
  'Unwind',
  'Liquidations',
  'eDai0',
  'eDai1',
  'eDai2',
  'eDai3',
  'eDai-2020-09-30-Pool',
  'eDai-2020-12-31-Pool',
  'eDai-2021-03-31-Pool',
  'eDai-2021-06-30-Pool',
]

const SIGNATURES = [
  'burn(address,uint256)',
  'mint(address,uint256)',

  'pushDai(address,uint256)',
  'pullDai(address,uint256)',

  'pushChai(address,uint256)',
  'pullChai(address,uint256)',

  'pushWeth(address,uint256)',
  'pullWeth(address,uint256)',

  'erase(address)',
  'erase(bytes32,address)',
].map((s) => ethers.utils.id(s).slice(0, 10))

const NAMES = [
  'BURN',
  'MINT',

  'PUSH_DAI',
  'PULL_DAI',

  'PUSH_CHAI',
  'PULL_CHAI',

  'PUSH_WETH',
  'PULL_WETH',

  'ERASE_AUCTION',
  'ERASE_VAULT',
]

;(async () => {
  const provider = new ethers.providers.JsonRpcProvider(ENDPOINT)
  const migrations = new ethers.Contract(MIGRATIONS, ABI, provider)
  const block = await provider.getBlockNumber()
  let data = {}
  data['block'] = block
  data['Migrations'] = { address: MIGRATIONS }

  for (const name of CONTRACTS) {
    // Get the contract from the registry
    const nameBytes = ethers.utils.formatBytes32String(name)
    const address = await migrations.contracts(nameBytes)
    const contract = new ethers.Contract(address, ABI, provider)

    // Get the logs
    const logs = await contract.queryFilter('GrantedAccess', START_BLOCK)
    const privileged = logs.map((log) => {
      const args = log.args
      const signature = args.signature
      const name = NAMES[SIGNATURES.indexOf(signature)]
      return { address: args.access, function: name || signature }
    })

    let owner
    try {
      owner = await contract.owner()
    } catch (e) {
      owner = ''
    }

    // save the data
    data[name] = {
      address: address,
      owner: owner,
      privileged: privileged,
    }
  }

  console.log(JSON.stringify(data))
})()
