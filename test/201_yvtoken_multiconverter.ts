import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import * as hre from 'hardhat'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants

import YVTokenMultiConverterArtifact from '../artifacts/contracts/other/yieldspace-tv/YVTokenMultiConverter.sol/YVTokenMultiConverter.json'

import { ERC20, YVTokenMultiConverter, YvTokenMock } from '../typechain'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
import { BigNumber } from 'ethers'
const { deployContract } = waffle

describe('YVTokenMultiConverter', function () {
  this.timeout(0)
  let yvMultiTokenConverter: YVTokenMultiConverter
  let ownerAcc: SignerWithAddress
  let yvusdcGov: SignerWithAddress
  let owner: string
  let usdc: ERC20
  let yvUSDC: ERC20
  const YVUSDC = '0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE'
  const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
  const YVUSDCGOVERNANCE = '0xFEB4acf3df3cDEA7399794D0869ef76A6EfAff52'

  before(async () => {
    ownerAcc = await ethers.getSigner('0xdb91f52eefe537e5256b8043e5f7c7f44d81f5aa')
    yvusdcGov = await ethers.getSigner(YVUSDCGOVERNANCE)
    // ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
    usdc = (await ethers.getContractAt('ERC20', USDC)) as unknown as ERC20
    yvUSDC = (await ethers.getContractAt('YvTokenMock', YVUSDC)) as unknown as YvTokenMock
    if (hre.network.name != 'tenderly') {
      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [owner],
      })
      await hre.network.provider.request({
        method: 'hardhat_setBalance',
        params: [owner, '0x1000000000000000000000'],
      })

      await hre.network.provider.request({
        method: 'hardhat_impersonateAccount',
        params: [YVUSDCGOVERNANCE],
      })
      await hre.network.provider.request({
        method: 'hardhat_setBalance',
        params: [YVUSDCGOVERNANCE, '0x1000000000000000000000'],
      })
    }
    yvMultiTokenConverter = (await deployContract(
      ownerAcc,
      YVTokenMultiConverterArtifact
    )) as unknown as YVTokenMultiConverter

    // Granting addMapping role
    await yvMultiTokenConverter.connect(ownerAcc).grantRole('0x6f6b6190', owner)

    await yvMultiTokenConverter.connect(ownerAcc).addMapping(USDC, YVUSDC)

    // await yvUSDC.connect(yvusdcGov).setGuestList(yvMultiTokenConverter.address)
  })

  it('wrappedFrom', async () => {
    expect(await yvMultiTokenConverter.callStatic.wrappedFrom(YVUSDC, BigNumber.from('158762760518'))).to.be.eq(
      '156324484858'
    )
  })

  it('assetFrom', async () => {
    expect(await yvMultiTokenConverter.callStatic.assetFrom(YVUSDC, BigNumber.from('144824814417'))).to.be.eq(
      '147083723635'
    )
  })

  it('wrappedFor', async () => {
    expect(await yvMultiTokenConverter.callStatic.wrappedFor(YVUSDC, BigNumber.from('158762760518'))).to.be.eq(
      '156324484858'
    )
  })

  it('assetFor', async () => {
    expect(await yvMultiTokenConverter.callStatic.assetFrom(YVUSDC, BigNumber.from('144824814417'))).to.be.eq(
      '147083723635'
    )
  })

  it('wrap', async () => {
    await usdc.connect(ownerAcc).transfer(yvMultiTokenConverter.address, BigNumber.from('1000000'))
    const beforeUSDC = await usdc.balanceOf(yvMultiTokenConverter.address)
    const beforeYvUSDC = await yvUSDC.balanceOf(owner)
    await yvMultiTokenConverter.wrap(YVUSDC, owner)
    const afterUSDC = await usdc.balanceOf(yvMultiTokenConverter.address)
    const afterYvUSDC = await yvUSDC.balanceOf(owner)
    expect(beforeUSDC).to.gt(afterUSDC)
    expect(beforeYvUSDC).to.lt(afterYvUSDC)
  })

  it('unwrap', async () => {
    const beforeUSDC = await usdc.balanceOf(owner)
    const beforeYvUSDC = await yvUSDC.balanceOf(owner)
    await yvUSDC.connect(ownerAcc).transfer(yvMultiTokenConverter.address, BigNumber.from('1000000'))
    await yvMultiTokenConverter.unwrap(YVUSDC, owner)
    const afterUSDC = await usdc.balanceOf(owner)
    const afterYvUSDC = await yvUSDC.balanceOf(owner)
    expect(beforeUSDC).to.lt(afterUSDC)
    expect(beforeYvUSDC).to.gt(afterYvUSDC)
  })
})
