import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { CHI, RATE } from '../src/constants'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import CompoundMultiOracleArtifact from '../artifacts/contracts/oracles/compound/CompoundMultiOracle.sol/CompoundMultiOracle.json'
import CTokenChiMockArtifact from '../artifacts/contracts/mocks/oracles/compound/CTokenChiMock.sol/CTokenChiMock.json'
import CTokenRateMockArtifact from '../artifacts/contracts/mocks/oracles/compound/CTokenRateMock.sol/CTokenRateMock.json'

import { CompoundMultiOracle } from '../typechain/CompoundMultiOracle'
import { CTokenMultiOracle } from '../typechain/CTokenMultiOracle'
import { CTokenChiMock } from '../typechain/CTokenChiMock'
import { CTokenRateMock } from '../typechain/CTokenRateMock'
import { UniswapV3Oracle } from '../typechain/UniswapV3Oracle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracles - Rate and Chi (Compound)', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let compoundMultiOracle: CompoundMultiOracle
  let cTokenChi: CTokenChiMock
  let cTokenRate: CTokenRateMock

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockBytes6 = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    cTokenChi = (await deployContract(ownerAcc, CTokenChiMockArtifact, [])) as CTokenChiMock
    cTokenRate = (await deployContract(ownerAcc, CTokenRateMockArtifact, [])) as CTokenRateMock

    compoundMultiOracle = (await deployContract(ownerAcc, CompoundMultiOracleArtifact)) as CompoundMultiOracle
    await compoundMultiOracle.grantRole(id(compoundMultiOracle.interface, 'setSource(bytes6,bytes6,address)'), owner)
    await compoundMultiOracle.setSource(baseId, CHI, cTokenChi.address)
    await compoundMultiOracle.setSource(baseId, RATE, cTokenRate.address)
  })

  it('revert on unknown sources', async () => {
    await expect(
      compoundMultiOracle.callStatic.get(bytes6ToBytes32(mockBytes6), bytes6ToBytes32(mockBytes6), WAD)
    ).to.be.revertedWith('Source not found')
  })

  it('sets and retrieves the chi and rate values at spot price from a compound multioracle', async () => {
    await cTokenChi.set(WAD.mul(2))
    await cTokenRate.set(WAD.mul(3))
    expect((await compoundMultiOracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(CHI), WAD))[0]).to.equal(
      WAD.mul(2)
    )
    expect((await compoundMultiOracle.callStatic.get(bytes6ToBytes32(baseId), bytes6ToBytes32(RATE), WAD))[0]).to.equal(
      WAD.mul(3)
    )

    expect((await compoundMultiOracle.peek(bytes6ToBytes32(baseId), bytes6ToBytes32(CHI), WAD))[0]).to.equal(WAD.mul(2))
    expect((await compoundMultiOracle.peek(bytes6ToBytes32(baseId), bytes6ToBytes32(RATE), WAD))[0]).to.equal(
      WAD.mul(3)
    )
  })
})
