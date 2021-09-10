import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants

import { sendStatic } from './shared/helpers'

import { Contract } from '@ethersproject/contracts'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import UniswapV3FactoryMockArtifact from '../artifacts/contracts/mocks/oracles/uniswap/UniswapV3FactoryMock.sol/UniswapV3FactoryMock.json'
import UniswapV3OracleArtifact from '../artifacts/contracts/oracles/uniswap/UniswapV3Oracle.sol/UniswapV3Oracle.json'

import { UniswapV3FactoryMock } from '../typechain/UniswapV3FactoryMock'
import { UniswapV3PoolMock } from '../typechain/UniswapV3PoolMock'
import { UniswapV3Oracle } from '../typechain/UniswapV3Oracle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracles - Uniswap', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let uniswapV3Factory: UniswapV3FactoryMock
  let uniswapV3Pool: UniswapV3PoolMock
  let uniswapV3PoolAddress: string
  let uniswapV3Oracle: UniswapV3Oracle

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ethQuoteId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    uniswapV3Factory = (await deployContract(ownerAcc, UniswapV3FactoryMockArtifact, [])) as UniswapV3FactoryMock
    const token0: string = ethers.utils.HDNode.fromSeed('0x0123456789abcdef0123456789abcdef').address
    const token1: string = ethers.utils.HDNode.fromSeed('0xfedcba9876543210fedcba9876543210').address
    uniswapV3PoolAddress = await sendStatic(uniswapV3Factory as Contract, 'createPool', ownerAcc, [token0, token1, 0])
    uniswapV3Pool = (await ethers.getContractAt('UniswapV3PoolMock', uniswapV3PoolAddress)) as UniswapV3PoolMock
    uniswapV3Oracle = (await deployContract(ownerAcc, UniswapV3OracleArtifact, [])) as UniswapV3Oracle
    await uniswapV3Oracle.grantRole(id(uniswapV3Oracle.interface, 'setSource(bytes6,bytes6,address)'), owner)
    await uniswapV3Oracle.setSource(baseId, ethQuoteId, uniswapV3PoolAddress)
  })

  it('retrieves the value at spot price from a uniswap v3 oracle', async () => {
    await uniswapV3Pool.set(WAD.mul(2))
    expect(
      (await uniswapV3Oracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(ethQuoteId), WAD))[0]
    ).to.equal(WAD.mul(2))
    expect(
      (await uniswapV3Oracle.callStatic.get(bytes6ToBytes32(ethQuoteId), bytes6ToBytes32(baseId), WAD))[0]
    ).to.equal(WAD.div(2))

    expect((await uniswapV3Oracle.peek(bytes6ToBytes32(baseId), bytes6ToBytes32(ethQuoteId), WAD))[0]).to.equal(
      WAD.mul(2)
    )
    expect((await uniswapV3Oracle.peek(bytes6ToBytes32(ethQuoteId), bytes6ToBytes32(baseId), WAD))[0]).to.equal(
      WAD.div(2)
    )
  })
})
