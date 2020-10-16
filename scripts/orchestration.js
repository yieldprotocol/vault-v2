// Script used to audit the permissions of Yield Protocol
// Defaults to the mainnet deployment
// This script may take a while to run.
//
// Run as `node orchestration.js`. Requires having `ethers v5` installed.
//
// Provide arguments as environment variables:
// - ENDPOINT: The Ethereum node to connect to
// - MIGRATIONS: The address of the smart contract registry
// - START_BLOCK: The block to filter events from (default: 0).
//   Do not set this to 0 if using with services like Infura
const ethers = require('ethers')

// defaults to the infura node
const ENDPOINT = process.env.ENDPOINT || 'https://mainnet.infura.io/v3/878c2840dbf943898a8b60b5faef8fe9'
// uses the mainnet deployment
const MIGRATIONS = process.env.MIGRATIONS || '0xd110Cfe9f35c5fDfB069606842744577577f50e5'
// migrations were deployed at https://etherscan.io/tx/0xbcd49ae3d5976bc7ad1e0e35de9ce5f21ffae01f4565c4fdc670d61abc233a70
const START_BLOCK = process.env.START_BLOCK || 11065032 // deployed block

// Human readable ABIs for Orchestrated contracts and for the registry
const ABI = [
  'event GrantedAccess(address access, bytes4 signature)',
  'function owner() view returns (address)',
  'function contracts(bytes32 name) view returns (address)',
  'function length() view returns (uint256)',
  'function names(uint i) view returns (bytes32)',
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


  let addressToName = {};
  let contracts = [];
  let names = [];

  const numContracts = await migrations.length()
  for (let i = 0; i < numContracts; i ++) {
    const nameBytes = await migrations.names(i)
    const address = await migrations.contracts(nameBytes)
    const contract = new ethers.Contract(address, ABI, provider)
    const name = ethers.utils.parseBytes32String(nameBytes)
    addressToName[address] = name
    contracts.push(contract)
    names.push(name)
  }

 for (const i in contracts) {
    // Get the logs
    const logs = await contracts[i].queryFilter('GrantedAccess', START_BLOCK)
    const privileged = logs.map((log) => {
      const args = log.args
      const signature = args.signature
      const fnName = NAMES[SIGNATURES.indexOf(signature)]
      const contractName = addressToName[args.access]
      return { caller: contractName || args.access, function: fnName || signature }
    })

    let owner
    try {
      owner = await contract.owner()
    } catch (e) {
      owner = ''
    }

    // save the data
    data[names[i]] = {
      address: contracts[i].address,
      owner: owner,
      privileged: privileged,
    }
  }

  console.log(JSON.stringify(data))
})()
