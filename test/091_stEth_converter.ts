import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

import { WstETHMock } from '../typechain/WstETHMock'
import { StEthConverter } from '../typechain/StEthConverter'
import { ERC20Mock } from '../typechain/ERC20Mock'

import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import WstETHMockArtifact from '../artifacts/contracts/mocks/WstETHMock.sol/WstETHMock.json'
import StEthConverterArtifact from '../artifacts/contracts/other/lido/StEthConverter.sol/StEthConverter.json'
import { parseEther } from '@ethersproject/units'

describe('Lido Wrapper-Unwrapper', function () {
  this.timeout(0)
  let ownerAcc: SignerWithAddress
  let dummyAcc: SignerWithAddress
  let owner: string
  let steth: ERC20Mock
  let wsteth: WstETHMock
  let lido: StEthConverter
  const amount = ethers.utils.parseEther('1')

  before(async () => {
    const signers = await ethers.getSigners()

    ownerAcc = signers[0]
    dummyAcc = signers[1]
    owner = await ownerAcc.getAddress()

    steth = (await deployContract(ownerAcc, ERC20MockArtifact, ['staked Ether 2.0', 'stETH'])) as ERC20Mock
    wsteth = (await deployContract(ownerAcc, WstETHMockArtifact, [steth.address])) as WstETHMock
    lido = (await deployContract(ownerAcc, StEthConverterArtifact, [wsteth.address, steth.address])) as StEthConverter

    await steth.mint(owner, parseEther('2'))
    await wsteth.mint(owner, amount)
  })

  it('should be able to wrap stETH', async () => {
    await steth['transfer(address,uint256)'](lido.address, amount)
    await lido.wrap(ownerAcc.address)
    expect(await steth.balanceOf(ownerAcc.address)).to.equal(parseEther('1'))
    expect(await wsteth.balanceOf(ownerAcc.address)).to.equal(parseEther('2'))
  })

  it('should be able to unwrap WstETH', async () => {
    await wsteth['transfer(address,uint256)'](lido.address, amount)
    await lido.unwrap(ownerAcc.address)
    expect(await steth.balanceOf(ownerAcc.address)).to.equal(parseEther('2'))
    expect(await wsteth.balanceOf(ownerAcc.address)).to.equal(amount)
  })

  it('should be able to wrap stETH & send resulting wstETH to another address', async () => {
    await steth['transfer(address,uint256)'](lido.address, amount)
    await lido.wrap(dummyAcc.address)
    expect(await steth.balanceOf(ownerAcc.address)).to.equal(parseEther('1'))
    expect(await wsteth.balanceOf(dummyAcc.address)).to.equal(parseEther('1'))
  })

  it('should be able to unwrap wstETH & send resulting stETH to another address', async () => {
    await steth['transfer(address,uint256)'](lido.address, amount)
    await lido.wrap(ownerAcc.address)
    await wsteth['transfer(address,uint256)'](lido.address, amount)
    await lido.unwrap(dummyAcc.address)
    expect(await steth.balanceOf(ownerAcc.address)).to.equal(0)
    expect(await steth.balanceOf(dummyAcc.address)).to.equal(amount)
  })

  it('should not be able to wrap stETH without transferring stETH first', async () => {
    await expect(lido.wrap(ownerAcc.address)).to.be.revertedWith('No stETH to wrap')
  })

  it('should not be able to unwrap wstETH without transferring wstETH first', async () => {
    await expect(lido.unwrap(ownerAcc.address)).to.be.revertedWith('No wstETH to unwrap')
  })
})
