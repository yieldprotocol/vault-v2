// Script used to debug the debt status of a user
//
// Run as `ADDRESS=0xYourAddress node debug_user.js`t
// Requires having `ethers v5` installed.
//
// Provide arguments as environment variables:
// - ENDPOINT: The Ethereum node to connect to
// - CONTROLLER: The address of the controller contract
// - ADDRESS: The address of the user you are inspecting
// - START_BLOCK: The block to filter events from (default: 0).
//   Do not set this to 0 if using with services like Infura
const ethers = require('ethers')
const fmtEth = ethers.utils.formatEther

// defaults to the infura node
const ENDPOINT = process.env.ENDPOINT || 'https://mainnet.infura.io/v3/878c2840dbf943898a8b60b5faef8fe9'
// uses the mainnet deployment
const CONTROLLER = process.env.CONTROLLER || '0xb94199866fe06b535d019c11247d3f921460b91a'
const START_BLOCK = process.env.START_BLOCK || 11065032 // deployed block

// which user to debug for
const USER = process.env.ADDRESS
if (USER === undefined) {
    console.error("Please set the ADDRESS environment variable with the user you want to inspect")
}

const ABI = [
    "event Posted(bytes32 indexed collateral, address indexed user, int256 amount)",
    "event Borrowed(bytes32 indexed collateral, uint256 indexed maturity, address indexed user, int256 amount)",

    "function seriesIterator(uint256 i) view returns (uint256)",
    "function posted(bytes32, address) view returns (uint256)",
    "function locked(bytes32, address) view returns (uint256)",
    "function debtFYDai(bytes32, uint256, address) view returns (uint256)",
    "function debtDai(bytes32, uint256, address) view returns (uint256)",
    "function isCollateralized(bytes32, address) view returns (bool)",
    "function powerOf(bytes32, address) view returns (uint256)",
    "function totalDebtDai(bytes32, address) view returns (uint256)",
]

const toDate = (ts)=> {
    const date = new Date(ts * 1000)
    return `${date.getMonth()}/${date.getFullYear()}`
}

const CHAI = ethers.utils.formatBytes32String("CHAI")
const ETH = ethers.utils.formatBytes32String("ETH-A")

;(async () => {
  const provider = new ethers.providers.JsonRpcProvider(ENDPOINT)
  const controller = new ethers.Contract(CONTROLLER, ABI, provider)
  const block = await provider.getBlockNumber()
  console.log(`Getting user ${USER} status at block ${block}`)
  console.log(`Controller: ${controller.address}\n`)

    // Get all the times they posted and borrowed
  const postedFilter = controller.filters.Posted(null, USER);
  let logs = await controller.queryFilter(postedFilter, START_BLOCK)
  const posted = logs.map((log) => {
      return {
          txhash: log.transactionHash,
          collateral: log.args.collateral,
          amount: log.args.amount.toString(),
      }
  })

  const borrowedFilter = controller.filters.Borrowed(null, null, USER);
  logs = await controller.queryFilter(borrowedFilter, START_BLOCK)
  const borrowed = logs.map((log) => {
      return {
          user: log.args.user,
          txhash: log.transactionHash,
          collateral: ethers.utils.parseBytes32String(log.args.collateral),
          maturity: toDate(log.args.maturity.toString()),
          amount: log.args.amount.toString(),
      }
  })

  console.log("User debt status:\n")
  for (const collateral of [CHAI, ETH]) {
      const ticker = ethers.utils.parseBytes32String(collateral)
      console.log(`Getting ${ticker} collateral info...`)
      const posted = await controller.posted(collateral, USER)
      const locked = await controller.locked(collateral, USER)
      const isOK = await controller.isCollateralized(collateral, USER)
      const borrowingPower = await controller.powerOf(collateral, USER)
      const totalDebtDai = await controller.totalDebtDai(collateral, USER)

      console.log("Is healthy?", isOK)
      console.log(`Total debt: ${fmtEth(totalDebtDai)} DAI`)
      console.log(`Can borrow: ${fmtEth(borrowingPower.sub(totalDebtDai))} DAI`)

      console.log(`Posted: ${fmtEth(posted)} ${ticker}`)
      console.log(`Locked: ${fmtEth(locked)} ${ticker}\n`)

      console.log("Getting per FYDai maturity info...")
      for (let i = 0; i < 6; i++) { // 6 fydai series
          const maturity = await controller.seriesIterator(i)
          console.log(`\tMaturity: ${toDate(maturity)}`)
          const debt = await controller.debtFYDai(collateral, maturity, USER)
          const inDai = await controller.debtDai(collateral, maturity, USER)
          console.log(`\tOwed: ${fmtEth(debt)} FYDAI (${fmtEth(inDai)} DAI)`)
          console.log() // newline
      }
  }

  console.log("History")
  console.log("User posted logs:")
  console.log(posted)

  console.log("User borrowed logs:")
  console.log(borrowed)
})()
