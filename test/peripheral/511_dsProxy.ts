const DSProxy = artifacts.require('DSProxy')
const DSProxyFactory = artifacts.require('DSProxyFactory')
const DSProxyRegistry = artifacts.require('ProxyRegistry')

import { Contract } from '../shared/fixtures'

contract('DSProxy', async (accounts) => {
  let [owner, user1] = accounts

  let proxyFactory: Contract
  let proxyRegistry: Contract

  beforeEach(async () => {
    // Setup DSProxyFactory and DSProxyCache
    proxyFactory = await DSProxyFactory.new({ from: owner })

    // Setup DSProxyRegistry
    proxyRegistry = await DSProxyRegistry.new(proxyFactory.address, { from: owner })
  })

  describe('User proxy setting', () => {
    it('sets a dsproxy for an user', async () => {
      await proxyRegistry.build({ from: user1 })
      const dsProxy = await DSProxy.at(await proxyRegistry.proxies(user1))

      assert.equal(await dsProxy.owner(), user1)
    })
  })
})
