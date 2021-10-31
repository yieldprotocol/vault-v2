import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { ETH, DAI, WSTETH } from '../src/constants'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { LidoOracle } from '../typechain/LidoOracle'
import { LidoMock } from '../typechain/LidoMock'
import LidoOracleArtifact from '../artifacts/contracts/oracles/lido/LidoOracle.sol/LidoOracle.json'
import LidoMockArtifact from '../artifacts/contracts/mocks/oracles/lido/LidoMock.sol/LidoMock.json'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
import { parseEther } from '@ethersproject/units'

const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracles - Chainlink', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let lidoOracle: LidoOracle
  let lidoMock: LidoMock

  const mockBytes6 = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
    lidoMock = (await deployContract(ownerAcc, LidoMockArtifact)) as LidoMock
    await lidoMock.set('1008339308050006006')
  })

  beforeEach(async () => {
    lidoOracle = (await deployContract(ownerAcc, LidoOracleArtifact)) as LidoOracle
    await lidoOracle.grantRole(id(lidoOracle.interface, 'setSource(address)'), owner)
    await lidoOracle['setSource(address)'](lidoMock.address) //mockOracle
  })

  it('sets and retrieves the value at spot price', async () => {
    expect((await lidoOracle.callStatic.get(bytes6ToBytes32(ETH), bytes6ToBytes32(WSTETH), WAD))[0]).to.equal(
      '991729660855795538'
    )
    expect(
      (await lidoOracle.callStatic.get(bytes6ToBytes32(WSTETH), bytes6ToBytes32(ETH), parseEther('1')))[0]
    ).to.equal('1008339308050006006')
  })

  it('revert on unknown sources', async () => {
    await expect(lidoOracle.callStatic.get(bytes6ToBytes32(DAI), bytes6ToBytes32(mockBytes6), WAD)).to.be.revertedWith(
      'Source not found'
    )
  })
})
