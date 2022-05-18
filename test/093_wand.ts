import { ethers, network, waffle } from 'hardhat'
import { YieldEnvironment } from './shared/fixtures'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { expect } from 'chai'
import { ETH, DAI, USDC } from '../src/constants'
import { Wand, Witch, Cauldron, Wandv2 } from '../typechain'
import Wandv2Artifact from '../artifacts/contracts/Wand-v2.sol/Wandv2.json'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { LadleWrapper } from '../src/ladleWrapper'
import { BigNumber } from '@ethersproject/bignumber'
const { deployContract } = waffle

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}
function bytesToString(bytes: string): string {
  return ethers.utils.parseBytes32String(bytes + '0'.repeat(66 - bytes.length))
}
function stringToBytes32(x: string): string {
  return ethers.utils.formatBytes32String(x)
}
function bytesToBytes32(bytes: string): string {
  return stringToBytes32(bytesToString(bytes))
}

/**
 * @dev This script tests the ConvexJoin and ConvexLadleModule integration with the Ladle
 */
describe('Wand-V2', async function () {
  this.timeout(0)

  let ladle: LadleWrapper
  let wand: Wand
  let witch: Witch
  let ownerAcc: SignerWithAddress
  let dummyAcc: SignerWithAddress
  let cauldron: Cauldron
  let wand2: Wandv2

  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId2 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId3 = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  let env: YieldEnvironment

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [USDC, DAI, ETH], [seriesId])
  }

  before(async () => {
    this.timeout(0)

    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    dummyAcc = signers[1]
    env = await fixture()
    ladle = env.ladle
    wand = env.wand
    witch = env.witch
    cauldron = env.cauldron

    wand2 = (await deployContract(ownerAcc, Wandv2Artifact, [cauldron.address, ladle.address])) as Wandv2

    //   it('Deploy a series', async () => {

    // await wand2.addSeries(
    //   seriesId3,
    //   USDC,
    //   BigNumber.from('1666094692'),
    //   [DAI, ETH],
    //   'temp',
    //   'temp',
    //   BigNumber.from('18446744073709551616').div(BigNumber.from('31557600').mul(37)),
    //   BigNumber.from('18446744073709551616').mul(80).div(100),
    //   BigNumber.from('18446744073709551616').mul(100).div(80)
    // )
    console.log('hello')
  })

  it('ads', async () => {
    console.log('hello2')
  })
})
