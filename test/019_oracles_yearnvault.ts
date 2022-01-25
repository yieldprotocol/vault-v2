import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
import { parseEther } from '@ethersproject/units'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { USDC, ETH, DAI, YVUSDC, YVDAI } from '../src/constants'

import { YearnVaultMultiOracle } from '../typechain/YearnVaultMultiOracle'
import { YvTokenMock } from '../typechain/YvTokenMock'
import { WETH9Mock } from '../typechain/WETH9Mock'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { USDCMock } from '../typechain/USDCMock'
import { DAIMock } from '../typechain/DAIMock'

import YearnVaultMultiOracleArtifact from '../artifacts/contracts/oracles/yearn/YearnVaultMultiOracle.sol/YearnVaultMultiOracle.json'
import YvTokenMockArtifact from '../artifacts/contracts/mocks/YvTokenMock.sol/YvTokenMock.json'
import WETH9MockArtifact from '../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import USDCMockArtifact from '../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'
import DAIMockArtifact from '../artifacts/contracts/mocks/DAIMock.sol/DAIMock.json'
import { BigNumber } from '@ethersproject/bignumber'

const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

describe('Oracles - Yearn Vault', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let usdc: USDCMock
  let dai: DAIMock
  let initialYvUSDCRate = '1083891' // 6 decimals
  let initialYvDAIRate = '1071594513314087964' // 18 decimals
  let yearnVaultMultiOracle: YearnVaultMultiOracle
  let yvUSDCMock: YvTokenMock
  let yvDAIMock: YvTokenMock

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    usdc = (await deployContract(ownerAcc, USDCMockArtifact)) as USDCMock
    yvUSDCMock = (await deployContract(ownerAcc, YvTokenMockArtifact, [
      'Yearn Vault USD Coin',
      'yvUSDC',
      6,
      usdc.address,
    ])) as YvTokenMock
    yvUSDCMock.set(BigNumber.from(initialYvUSDCRate))

    dai = (await deployContract(ownerAcc, DAIMockArtifact)) as DAIMock
    yvDAIMock = (await deployContract(ownerAcc, YvTokenMockArtifact, [
      'Yearn Vault DAI',
      'yvDAI',
      18,
      dai.address,
    ])) as YvTokenMock
    yvDAIMock.set(BigNumber.from(initialYvDAIRate))

    yearnVaultMultiOracle = (await deployContract(ownerAcc, YearnVaultMultiOracleArtifact, [])) as YearnVaultMultiOracle
    await yearnVaultMultiOracle.grantRole(
      id(yearnVaultMultiOracle.interface, 'setSource(bytes6,bytes6,address)'),
      owner
    )
  })

  it('get() reverts if pair not found', async () => {
    console.log('hello')
    await expect(
      yearnVaultMultiOracle.callStatic.get(bytes6ToBytes32(YVUSDC), bytes6ToBytes32(USDC), '2' + '000000')
    ).to.be.revertedWith('Source not found')
  })

  it('setSource() sets a pair and the inverse pair', async () => {
    //Set yvUSDC/USDC yearn vault oracle
    await expect(yearnVaultMultiOracle.setSource(USDC, YVUSDC, yvUSDCMock.address))
      .to.emit(yearnVaultMultiOracle, 'SourceSet')
      .withArgs(USDC, YVUSDC, yvUSDCMock.address, 6)

    await expect(yearnVaultMultiOracle.callStatic.get(bytes6ToBytes32(USDC), bytes6ToBytes32(YVUSDC), '2' + '000000'))
      .not.to.be.reverted
  })

  describe('with sources set', function () {
    beforeEach(async () => {
      await yearnVaultMultiOracle.setSource(USDC, YVUSDC, yvUSDCMock.address)
      await yearnVaultMultiOracle.setSource(DAI, YVDAI, yvDAIMock.address)
    })

    it('get() and peek() return correct values', async () => {
      expect(
        (await yearnVaultMultiOracle.callStatic.get(bytes6ToBytes32(YVUSDC), bytes6ToBytes32(USDC), '2' + '000000'))[0]
      ).to.equal(BigNumber.from(initialYvUSDCRate).mul(2).toString())
      expect((await yearnVaultMultiOracle.peek(bytes6ToBytes32(YVDAI), bytes6ToBytes32(DAI), WAD.mul(2)))[0]).to.equal(
        BigNumber.from(initialYvDAIRate).mul(2).toString()
      )

      // check inverted pairs
      const invertedYvUSDCRate = parseInt(((1 / parseFloat(initialYvUSDCRate)) * 10 ** 12).toString()).toString()
      expect(
        (await yearnVaultMultiOracle.callStatic.get(bytes6ToBytes32(USDC), bytes6ToBytes32(YVUSDC), '1000000'))[0]
      ).to.equal(BigNumber.from(invertedYvUSDCRate).toString())

      expect((await yearnVaultMultiOracle.peek(bytes6ToBytes32(DAI), bytes6ToBytes32(YVDAI), WAD))[0]).to.equal(
        WAD.mul(WAD).div(BigNumber.from(initialYvDAIRate)).toString()
      )

      // change price
      const newPrice = '1088888'
      await yvUSDCMock.set(newPrice)
      expect(
        (await yearnVaultMultiOracle.callStatic.get(bytes6ToBytes32(YVUSDC), bytes6ToBytes32(USDC), '2' + '000000'))[0]
      ).to.equal(BigNumber.from(newPrice).mul(2).toString())
    })

    it('get() reverts on zero price ', async () => {
      await yvUSDCMock.set(0)
      await expect(
        yearnVaultMultiOracle.get(bytes6ToBytes32(YVUSDC), bytes6ToBytes32(USDC), '2' + '000000')
      ).to.be.revertedWith('Zero price')
    })
  })
})
