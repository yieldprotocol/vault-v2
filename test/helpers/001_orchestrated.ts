const Orchestrated = artifacts.require('Orchestrated')

// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers'
import { id } from 'ethers/lib/utils'
import { assert } from 'chai'

contract('Orchestrated', async (accounts: string[]) => {
  let [owner, other] = accounts

  let orchestrated: any

  beforeEach(async () => {
    orchestrated = await Orchestrated.new()
  })

  it('non-admin cannot orchestrate', async () => {
    const mintSignature = id('mint(address,uint256)')
    await expectRevert.unspecified(orchestrated.orchestrate(owner, mintSignature, { from: other }))
  })

  it('can orchestrate', async () => {
    const mintSignature = id('mint(address,uint256)')
    await orchestrated.orchestrate(owner, mintSignature)
    expect(await orchestrated.orchestration(owner, mintSignature)).to.be.true
  })

  it('can batch orchestrate', async () => {
    const sigs = ['mint', 'burn', 'transfer'].map((sig) => id(sig + '(address,uint256)'))
    await orchestrated.batchOrchestrate(owner, sigs)
    for (const sig of sigs) {
      expect(await orchestrated.orchestration(owner, sig)).to.be.true
    }
  })
})
