const ERC20 = artifacts.require('OrchestratedERC20')
const Minter = artifacts.require('Minter')

// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers'
import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'
import { assert } from 'chai'

contract('Orchestrated', async (accounts: string[]) => {
  let [owner, user] = accounts

  let erc20: any
  let minter: any

  beforeEach(async () => {
    erc20 = await ERC20.new('Name', 'Symbol', { from: owner })
    minter = await Minter.new({ from: owner })
  })

  it('does not allow minting to unknown addresses', async () => {
    await expectRevert(
        minter.mint(erc20.address, owner, 1, { from: owner }),
        'OrchestratedERC20: mint'
      )
  })

  it('allows minting to orchestrated addresses for specified function', async () => {
    const mintSignature = keccak256(toUtf8Bytes('mint(address,uint256)')).slice(0,10) // 0x + 2 * 4 bytes
    await erc20.orchestrate(minter.address, mintSignature, { from: owner })
    await minter.mint(erc20.address, owner, 1, { from: owner })
    assert.equal(await erc20.balanceOf(owner), 1)
  })

  it('does not allow minting if given different permission', async () => {
    const burnSignature = keccak256(toUtf8Bytes('burn(address,uint256)')).slice(0,10)
    await erc20.orchestrate(minter.address, burnSignature, { from: owner })
    await expectRevert(
        minter.mint(erc20.address, owner, 1, { from: owner }),
        'OrchestratedERC20: mint'
      )
  })
})
