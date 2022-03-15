import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id, constants } from '@yield-protocol/utils-v2'
const { WAD, MAX256 } = constants

import WETH9MockArtifact from '../artifacts/contracts/mocks/WETH9Mock.sol/WETH9Mock.json'
import WrapEtherModuleArtifact from '../artifacts/contracts/other/ether/WrapEtherModule.sol/WrapEtherModule.json'

import { WETH9Mock } from '../typechain/WETH9Mock'
import { Cauldron } from '../typechain/Cauldron'
import { WrapEtherModule } from '../typechain/WrapEtherModule'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'
import { ETH } from '../src/constants'

describe('Ladle - module', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let ladle: LadleWrapper
  let weth: WETH9Mock
  let wrapEtherModule: WrapEtherModule
  
  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [], [])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
    other = await signers[1].getAddress()
  })

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    weth = (await ethers.getContractAt('WETH9Mock', (await ladle.ladle.weth()) as string)) as WETH9Mock

    // ==== Set Module ====
    wrapEtherModule = (await deployContract(ownerAcc, WrapEtherModuleArtifact, [
      cauldron.address,
      weth.address,
    ])) as WrapEtherModule
    await ladle.grantRoles([id(ladle.ladle.interface, 'addToken(address,bool)')], owner)
    await ladle.grantRoles([id(ladle.ladle.interface, 'addModule(address,bool)')], owner)

    await ladle.addModule(wrapEtherModule.address, true)
  })

  it('wraps Ether to a destination through the ladle', async () => {
    const calldata = wrapEtherModule.interface.encodeFunctionData('wrap', [
      other,
      WAD
    ])
    await ladle.ladle.moduleCall(wrapEtherModule.address, calldata, { value: WAD })
    expect(await weth.balanceOf(other)).to.equal(WAD)
  })
})
