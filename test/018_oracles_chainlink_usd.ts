import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { CHI, RATE } from '../src/constants'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { ethers, waffle, artifacts, network } from 'hardhat'
import { expect } from 'chai'
import {
  ChainlinkUSDMultiOracle,
  ChainlinkL2USDMultiOracle,
  ERC20,
  ChainlinkAggregatorV3MockEx,
  FlagsInterfaceMock,
} from '../typechain'
import { BigNumber } from '@ethersproject/bignumber'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('ChainlinkUSDMultiOracle', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let oracleL1: ChainlinkUSDMultiOracle
  let oracleL2: ChainlinkL2USDMultiOracle
  let flagsL2: FlagsInterfaceMock

  let tokenA: ERC20
  let tokenB: ERC20

  const baseId1 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const base1 = bytes6ToBytes32(baseId1)
  const baseId2 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const base2 = bytes6ToBytes32(baseId2)

  function getOracle(l: number) {
    if (l == 1) {
      return oracleL1
    }
    if (l == 2) {
      return oracleL2
    }
    throw new Error(`Can't find oracle for ${l}`)
  }

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
    // l1 oracle
    oracleL1 = (await deployContract(
      ownerAcc,
      await artifacts.readArtifact('ChainlinkUSDMultiOracle'),
      []
    )) as ChainlinkUSDMultiOracle
    await oracleL1.grantRole(id(oracleL1.interface, 'setSource(bytes6,address,address)'), owner)

    // l2 oracle
    flagsL2 = (await deployContract(
      ownerAcc,
      await artifacts.readArtifact('FlagsInterfaceMock'),
      []
    )) as FlagsInterfaceMock
    oracleL2 = (await deployContract(ownerAcc, await artifacts.readArtifact('ChainlinkL2USDMultiOracle'), [
      flagsL2.address,
    ])) as ChainlinkL2USDMultiOracle
    await oracleL2.grantRole(id(oracleL2.interface, 'setSource(bytes6,address,address)'), owner)

    // tokens
    tokenA = await genToken(6)
    tokenB = await genToken(18)
  })

  for (const oracle_l of [1, 2]) {
    it(`can not get price when one of the sources is not set: L${oracle_l}`, async () => {
      const oracle = getOracle(oracle_l)
      // base and quote are missing
      await expect(oracle.peek(base1, base2, WAD)).to.be.revertedWith('Source not found')
      await oracle.setSource(baseId1, tokenA.address, (await genChainlinkAggregatorMock(8, BigNumber.from(1))).address)
      // quote is missing
      await expect(oracle.peek(base1, base2, WAD)).to.be.revertedWith('Source not found')
      // base is missing
      await expect(oracle.peek(base2, base1, WAD)).to.be.revertedWith('Source not found')
    })

    it(`does not allow non-8-digit USD sources: L${oracle_l}`, async () => {
      const oracle = getOracle(oracle_l)
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
      it(`converts correctly: a=${a_in_usd}; b=${b_in_usd}: : L${oracle_l}`, async () => {
        const oracle = getOracle(oracle_l)
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
  }

  it("L2 oracle can't fetch prices if the sequencer is down", async () => {
    const oracle = getOracle(2)

    const tokenA_oracle = await genChainlinkAggregatorMock(8, WAD)
    // 1 tokenB == 1 USD
    const tokenB_oracle = await genChainlinkAggregatorMock(8, WAD)

    await oracle.setSource(baseId1, tokenA.address, tokenA_oracle.address)
    await oracle.setSource(baseId2, tokenB.address, tokenB_oracle.address)

    await flagsL2.flagSetArbitrumSeqOffline(true)
    await expect(oracle.peek(base1, base2, WAD)).to.be.revertedWith('Chainlink feeds are not being updated')

    await flagsL2.flagSetArbitrumSeqOffline(false)
    await oracle.peek(base1, base2, WAD) // expect to recover
  })
})
