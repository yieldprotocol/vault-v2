import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { DAI, USDC } from '../src/constants'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import CTokenMultiOracleArtifact from '../artifacts/contracts/oracles/compound/CTokenMultiOracle.sol/CTokenMultiOracle.json'
import DAIMockArtifact from '../artifacts/contracts/mocks/DAIMock.sol/DAIMock.json'
import USDCMockArtifact from '../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'
import CTokenMockArtifact from '../artifacts/contracts/mocks/oracles/compound/CTokenMock.sol/CTokenMock.json'

import { CTokenMultiOracle } from '../typechain/CTokenMultiOracle'
import { DAIMock } from '../typechain/DAIMock'
import { USDCMock } from '../typechain/USDCMock'
import { CTokenMock } from '../typechain/CTokenMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracles - cToken', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let cTokenMultiOracle: CTokenMultiOracle
  let dai: DAIMock
  let usdc: USDCMock
  let cDai: CTokenMock
  let cUSDC: CTokenMock

  const cDaiId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const cUSDCId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockBytes6 = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    dai = (await deployContract(ownerAcc, DAIMockArtifact)) as DAIMock
    usdc = (await deployContract(ownerAcc, USDCMockArtifact)) as USDCMock
    cDai = (await deployContract(ownerAcc, CTokenMockArtifact, [dai.address])) as CTokenMock
    cUSDC = (await deployContract(ownerAcc, CTokenMockArtifact, [usdc.address])) as CTokenMock

    cTokenMultiOracle = (await deployContract(ownerAcc, CTokenMultiOracleArtifact)) as CTokenMultiOracle
    await cTokenMultiOracle.grantRole(id(cTokenMultiOracle.interface, 'setSource(bytes6,bytes6,address)'), owner)
    await cTokenMultiOracle.setSource(cDaiId, DAI, cDai.address)
    await cTokenMultiOracle.setSource(cUSDCId, USDC, cUSDC.address)
  })

  it('revert on unknown sources', async () => {
    await expect(
      cTokenMultiOracle.callStatic.get(bytes6ToBytes32(mockBytes6), bytes6ToBytes32(mockBytes6), WAD)
    ).to.be.revertedWith('Source not found')
  })

  it('sets and retrieves the cToken spot price from a cToken multioracle', async () => {
    await cDai.set(WAD.mul(2).mul(10 ** 10)) // cDai has 18 + 10 decimals
    await cUSDC.set(WAD.mul(2).div(100)) // USDC has 6 + 10 decimals

    expect((await cTokenMultiOracle.callStatic.get(bytes6ToBytes32(cDaiId), bytes6ToBytes32(DAI), WAD))[0]).to.equal(
      WAD.mul(2)
    )
    expect((await cTokenMultiOracle.callStatic.get(bytes6ToBytes32(cUSDCId), bytes6ToBytes32(USDC), WAD))[0]).to.equal(
      WAD.mul(2)
    )
    expect((await cTokenMultiOracle.callStatic.get(bytes6ToBytes32(DAI), bytes6ToBytes32(cDaiId), WAD))[0]).to.equal(
      WAD.div(2)
    )

    expect((await cTokenMultiOracle.peek(bytes6ToBytes32(cDaiId), bytes6ToBytes32(DAI), WAD))[0]).to.equal(WAD.mul(2))
    expect((await cTokenMultiOracle.peek(bytes6ToBytes32(cUSDCId), bytes6ToBytes32(USDC), WAD))[0]).to.equal(WAD.mul(2))
    expect((await cTokenMultiOracle.peek(bytes6ToBytes32(DAI), bytes6ToBytes32(cDaiId), WAD))[0]).to.equal(WAD.div(2))
  })
})
