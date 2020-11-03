const EthProxy = artifacts.require('YieldProxy')
const DSProxy = artifacts.require('DSProxy')
const DSProxyFactory = artifacts.require('DSProxyFactory')
const DSProxyRegistry = artifacts.require('ProxyRegistry')

const { id } = require('ethers/lib/utils')

// @ts-ignore
import helper from 'ganache-time-traveler'
import { wethTokens1 } from '../shared/utils'
import { YieldEnvironmentLite, Contract } from '../shared/fixtures'

contract('DSProxy', async (accounts) => {
  let [owner, user1, user2] = accounts

  let snapshot: any
  let snapshotId: string

  let vat: Contract
  let weth: Contract
  let treasury: Contract
  let controller: Contract

  let ethProxy: Contract
  let proxyFactory: Contract
  let proxyRegistry: Contract

  let maturity1: number
  let maturity2: number

  beforeEach(async () => {
    snapshot = await helper.takeSnapshot()
    snapshotId = snapshot['result']

    // Setup fyDai
    const block = await web3.eth.getBlockNumber()
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000
    maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000

    const env = await YieldEnvironmentLite.setup([maturity1, maturity2])
    controller = env.controller
    treasury = env.treasury
    vat = env.maker.vat
    weth = env.maker.weth

    // Setup EthProxy
    ethProxy = await EthProxy.new(env.controller.address, [])

    // Setup DSProxyFactory and DSProxyCache
    proxyFactory = await DSProxyFactory.new({ from: owner })

    // Setup DSProxyRegistry
    proxyRegistry = await DSProxyRegistry.new(proxyFactory.address, { from: owner })
  })

  afterEach(async () => {
    await helper.revertToSnapshot(snapshotId)
  })

  describe('User proxy setting', () => {
    it('sets a dsproxy for an user', async () => {
      await proxyRegistry.build({ from: user1 })
      const dsProxy = await DSProxy.at(await proxyRegistry.proxies(user1))

      assert.equal(
        await dsProxy.owner(),
        user1
      )
    })
  })

  describe('without onboarding', () => {
    beforeEach(async () => {
      // Build a dsproxy for user1
      await proxyRegistry.build({ from: user1 })
    })

    it('post through ethProxy', async () => {
      await ethProxy.post(user1, { from: user1, value: wethTokens1 })
    })

    it('post through dsproxy', async () => {
      console.log(ethProxy.contract)

      const dsProxy = await DSProxy.at(await proxyRegistry.proxies(user1))
      const calldata = ethProxy.contract.post(user1).encodeABI()

      console.log(calldata)
      console.log(id('post(address)').slice(0, 10))
      console.log(user1)
      await dsProxy.execute(ethProxy.address, calldata, { from: user1, value: wethTokens1 })
    })
  })
})
