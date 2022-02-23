import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { DAI, USDC } from '../src/constants'

import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import NotionalMultiOracleArtifact from '../artifacts/contracts/other/notional/NotionalMultiOracle.sol/NotionalMultiOracle.json'
import DAIMockArtifact from '../artifacts/contracts/mocks/DAIMock.sol/DAIMock.json'
import USDCMockArtifact from '../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'

import { IOracle } from '../typechain/IOracle'
import { NotionalMultiOracle } from '../typechain/NotionalMultiOracle'
import { DAIMock } from '../typechain/DAIMock'
import { USDCMock } from '../typechain/USDCMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracles - Notional', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let oracle: IOracle
  let notionalMultiOracle: NotionalMultiOracle
  let dai: DAIMock
  let usdc: USDCMock
  const FDAI = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const FUSDC = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  const oneUSDC = WAD.div(1000000000000)

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  beforeEach(async () => {
    dai = (await deployContract(ownerAcc, DAIMockArtifact)) as DAIMock
    usdc = (await deployContract(ownerAcc, USDCMockArtifact)) as USDCMock

    notionalMultiOracle = (await deployContract(ownerAcc, NotionalMultiOracleArtifact, [])) as NotionalMultiOracle
    await notionalMultiOracle.grantRole(id(notionalMultiOracle.interface, 'setSource(bytes6,bytes6,address)'), owner)
    await notionalMultiOracle.setSource(FDAI, DAI, dai.address)
    await notionalMultiOracle.setSource(USDC, FUSDC, usdc.address)
  })

  it('revert on unknown sources', async () => {
    await expect(
      notionalMultiOracle.callStatic.get(bytes6ToBytes32(FDAI), bytes6ToBytes32(USDC), WAD)
    ).to.be.revertedWith('Source not found')
  })

  it('returns the input when baseId == quoteId', async () => {
    expect(
      (await notionalMultiOracle.callStatic.get(bytes6ToBytes32(FDAI), bytes6ToBytes32(FDAI), WAD.mul(2500)))[0]
    ).to.equal(WAD.mul(2500))
  })

  it('retrieves the face value from a notional multioracle', async () => {
    expect(
      (await notionalMultiOracle.callStatic.get(bytes6ToBytes32(FDAI), bytes6ToBytes32(DAI), WAD.mul(2500)))[0]
    ).to.equal(WAD.mul(2500))
    expect(
      (await notionalMultiOracle.callStatic.get(bytes6ToBytes32(FUSDC), bytes6ToBytes32(USDC), WAD.mul(2500)))[0]
    ).to.equal(oneUSDC.mul(2500))
    expect(
      (await notionalMultiOracle.callStatic.get(bytes6ToBytes32(DAI), bytes6ToBytes32(FDAI), WAD.mul(2500)))[0]
    ).to.equal(WAD.mul(2500))
    expect((await notionalMultiOracle.callStatic.get(bytes6ToBytes32(USDC), bytes6ToBytes32(FUSDC), oneUSDC.mul(2500)))[0]).to.equal(
      WAD.mul(2500)
    )
  })
})
