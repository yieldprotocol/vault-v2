import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
import { parseEther } from '@ethersproject/units'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { USDC, ETH, DAI, YVUSDC, YVDAI } from '../src/constants'

import { YearnVaultMultiOracle } from '../typechain/YearnVaultMultiOracle'
import { YearnVaultMock } from '../typechain/YearnVaultMock'
import { WETH9Mock } from '../typechain/WETH9Mock'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { USDCMock } from '../typechain/USDCMock'

import YearnVaultMultiOracleArtifact from '../artifacts/contracts/oracles/yearn/YearnVaultMultiOracle.sol/YearnVaultMultiOracle.json'
import YearnVaultMockArtifact from '../artifacts/contracts/mocks/YearnVaultMock.sol/YearnVaultMock.json'
import WETH9MockArtifact from '../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import USDCMockArtifact from '../artifacts/contracts/mocks/USDCMock.sol/USDCMock.json'
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
  let initialYvUSDCRate = '1083891' // 6 decimals
  let initialYvDAIRate = '1071594513314087964' // 18 decimals
  let yearnVaultMultiOracle: YearnVaultMultiOracle
  let yvUSDCMock: YearnVaultMock
  let yvDAIMock: YearnVaultMock

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    yvUSDCMock = (await deployContract(ownerAcc, YearnVaultMockArtifact, [
      'Yearn Vault USD Coin',
      'yvUSDC',
      6,
      BigNumber.from(initialYvUSDCRate),
    ])) as YearnVaultMock

    yvDAIMock = (await deployContract(ownerAcc, YearnVaultMockArtifact, [
      'Yearn Vault DAI',
      'yvDAI',
      18,
      BigNumber.from(initialYvDAIRate),
    ])) as YearnVaultMock

    usdc = (await deployContract(ownerAcc, USDCMockArtifact)) as USDCMock

    yearnVaultMultiOracle = (await deployContract(ownerAcc, YearnVaultMultiOracleArtifact, [])) as YearnVaultMultiOracle
    await yearnVaultMultiOracle.grantRole(
      id(yearnVaultMultiOracle.interface, 'setSource(bytes6,bytes6,address)'),
      owner
    )
  })

  it('get() reverts if pair not found', async () => {
    await expect(
      yearnVaultMultiOracle.get(bytes6ToBytes32(YVUSDC), bytes6ToBytes32(USDC), '2' + '000000')
    ).to.be.revertedWith('Source not found')
  })

  it('setSource() sets a pair and the inverse pair', async () => {
    //Set yvUSDC/USDC yearn vault oracle
    await expect(yearnVaultMultiOracle.setSource(YVUSDC, USDC, yvUSDCMock.address))
      .to.emit(yearnVaultMultiOracle, 'SourceSet')
      .withArgs(YVUSDC, USDC, yvUSDCMock.address, 6)

    await expect(yearnVaultMultiOracle.get(bytes6ToBytes32(USDC), bytes6ToBytes32(YVUSDC), '2' + '000000')).not.to.be
      .reverted
  })

  describe('with sources set', function () {
    beforeEach(async () => {
      await yearnVaultMultiOracle.setSource(YVUSDC, USDC, yvUSDCMock.address)
      await yearnVaultMultiOracle.setSource(YVDAI, DAI, yvDAIMock.address)
    })

    it('get() and peek() return correct values', async () => {
      expect(
        (await yearnVaultMultiOracle.get(bytes6ToBytes32(YVUSDC), bytes6ToBytes32(USDC), '2' + '000000'))[0]
      ).to.equal(BigNumber.from(initialYvUSDCRate).mul(2).toString())
      expect((await yearnVaultMultiOracle.peek(bytes6ToBytes32(YVDAI), bytes6ToBytes32(DAI), WAD.mul(2)))[0]).to.equal(
        BigNumber.from(initialYvDAIRate).mul(2).toString()
      )

      // check inverted pairs
      const invertedYvUSDCRate = parseInt(((1 / parseFloat(initialYvUSDCRate)) * 10 ** 12).toString()).toString()
      expect((await yearnVaultMultiOracle.get(bytes6ToBytes32(USDC), bytes6ToBytes32(YVUSDC), '1000000'))[0]).to.equal(
        BigNumber.from(invertedYvUSDCRate).toString()
      )

      expect((await yearnVaultMultiOracle.peek(bytes6ToBytes32(DAI), bytes6ToBytes32(YVDAI), WAD))[0]).to.equal(
        WAD.mul(WAD).div(BigNumber.from(initialYvDAIRate)).toString()
      )

      // change price
      const newPrice = '1088888'
      await yvUSDCMock.setPrice(newPrice)
      expect(
        (await yearnVaultMultiOracle.get(bytes6ToBytes32(YVUSDC), bytes6ToBytes32(USDC), '2' + '000000'))[0]
      ).to.equal(BigNumber.from(newPrice).mul(2).toString())
    })

    it('get() reverts on zero price ', async () => {
      await yvUSDCMock.setPrice(0)
      await expect(
        yearnVaultMultiOracle.get(bytes6ToBytes32(YVUSDC), bytes6ToBytes32(USDC), '2' + '000000')
      ).to.be.revertedWith('Zero price')
    })
  })
})
