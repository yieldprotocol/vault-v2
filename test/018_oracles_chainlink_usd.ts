import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { CHI, RATE } from '../src/constants'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { ethers, waffle, artifacts, network } from 'hardhat'
import { expect } from 'chai'
import { ChainlinkUSDMultiOracle, ERC20, ChainlinkAggregatorV3MockEx } from '../typechain'
import { BigNumber } from '@ethersproject/bignumber'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('ChainlinkUSDMultiOracle', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let oracle: ChainlinkUSDMultiOracle

  let tokenA: ERC20
  let tokenB: ERC20

  const baseId1 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const base1 = bytes6ToBytes32(baseId1)
  const baseId2 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const base2 = bytes6ToBytes32(baseId2)

  async function genToken(decimals: number): Promise<ERC20> {
    return (await deployContract(ownerAcc, await artifacts.readArtifact('ERC20'), [
      `name_${decimals}`,
      `symbol_${decimals}`,
      decimals,
    ])) as ERC20
  }

  async function genChainlinkAggregatorMock(decimals: number, price: BigNumber): Promise<ChainlinkAggregatorV3MockEx> {
    const ret = (await deployContract(ownerAcc, await artifacts.readArtifact('ChainlinkAggregatorV3MockEx'), [
      decimals,
    ])) as ChainlinkAggregatorV3MockEx

    await ret.set(price.toString())
    return ret
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    oracle = (await deployContract(
      ownerAcc,
      await artifacts.readArtifact('ChainlinkUSDMultiOracle'),
      []
    )) as ChainlinkUSDMultiOracle
    await oracle.grantRole(id(oracle.interface, 'setSource(bytes6,address,address)'), owner)

    tokenA = await genToken(6)
    tokenB = await genToken(18)
  })

  it('can not get price when one of the sources is not set', async () => {
    // base and quote are missing
    await expect(oracle.peek(base1, base2, WAD)).to.be.revertedWith('Source not found')
    await oracle.setSource(baseId1, tokenA.address, (await genChainlinkAggregatorMock(8, BigNumber.from(1))).address)
    // quote is missing
    await expect(oracle.peek(base1, base2, WAD)).to.be.revertedWith('Source not found')
    // base is missing
    await expect(oracle.peek(base2, base1, WAD)).to.be.revertedWith('Source not found')
  })

  it('does not allow non-8-digit USD sources', async () => {
    // base and quote are missing
    await expect(
      oracle.setSource(baseId1, tokenA.address, (await genChainlinkAggregatorMock(18, BigNumber.from(1))).address)
    ).to.be.revertedWith('Non-8-decimals USD source')
  })

  // BigNumber doesn't support real numbers -> we use WADs
  for (const [a_in_usd, b_in_usd, expected_b_for_1_a_in_WAD] of [
    [1, 1, WAD], // 1 a = 1 USD, 1 b = 1 USD, 1 a = 1 b
    [1, 2, WAD.div(2)], // 1 a = 1 USD, 1 b = 2 USD, 1 a = 1/2 b
    [10, 1, WAD.mul(10)], // 1 a = 10 USD, 1 b = 1 USD, 1 a = 10 b
    [100, 700, WAD.div(7)], // 1 a = 100 USD, 1 b = 700 USD, 1 a = 1/7 b
  ]) {
    it(`converts correctly: a=${a_in_usd}; b=${b_in_usd}`, async () => {
      // 1 tokenA == 1 USD
      const tokenA_oracle = await genChainlinkAggregatorMock(8, BigNumber.from(10).pow(8).mul(a_in_usd))
      // 1 tokenB == 1 USD
      const tokenB_oracle = await genChainlinkAggregatorMock(8, BigNumber.from(10).pow(8).mul(b_in_usd))

      await oracle.setSource(baseId1, tokenA.address, tokenA_oracle.address)
      await oracle.setSource(baseId2, tokenB.address, tokenB_oracle.address)

      // a -> b
      const a_amount = BigNumber.from(10)
        .pow(await tokenA.decimals())
        .mul(100) // 100 tokens
      const expected_b_amount = a_amount.mul(expected_b_for_1_a_in_WAD).div(WAD).mul(BigNumber.from(10).pow(12)) // b has 12 more digits

      expect((await oracle.peek(base1, base2, a_amount.toString()))[0]).to.be.equal(expected_b_amount.toString())

      // b -> a
      const b_amount = BigNumber.from(10)
        .pow(await tokenB.decimals())
        .mul(100) // 100 tokens
      const expected_a_amount = b_amount
        .mul(WAD)
        .div(BigNumber.from(expected_b_for_1_a_in_WAD))
        .div(BigNumber.from(10).pow(12)) // a has 12 fewer digits

      expect((await oracle.peek(base2, base1, b_amount.toString()))[0]).to.be.equal(expected_a_amount.toString())
    })
  }
})
