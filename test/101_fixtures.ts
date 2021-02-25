import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import CauldronArtifact from '../artifacts/contracts/Cauldron.sol/Cauldron.json'
import JoinArtifact from '../artifacts/contracts/Join.sol/Join.json'
import FYTokenArtifact from '../artifacts/contracts/FYToken.sol/FYToken.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import LadleArtifact from '../artifacts/contracts/Ladle.sol/Ladle.json'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
// import { id } from '../src'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'

describe('Fixtures', () => {
  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock
  let ilkJoin: Join
  let ladle: Ladle
  let ladleFromOther: Ladle

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const ilkId1 = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const ilkId2 = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6));

  beforeEach(async () => {
    env = await loadFixture(fixture);
  })

  // TODO: Do actual tests
  it('dummy test', async () => {
    // console.log(env)
  })
})
