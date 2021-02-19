import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import VatArtifact from '../artifacts/contracts/Vat.sol/Vat.json'
import JoinArtifact from '../artifacts/contracts/Join.sol/Join.json'
import FYTokenArtifact from '../artifacts/contracts/FYToken.sol/FYToken.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import CDPProxyArtifact from '../artifacts/contracts/CDPProxy.sol/CDPProxy.json'

import { Vat } from '../typechain/Vat'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { CDPProxy } from '../typechain/CDPProxy'

import { ethers, waffle } from 'hardhat'
// import { id } from '../src'
import { expect } from 'chai'
const { deployContract } = waffle

import { YieldEnvironment } from './shared/fixtures'

describe('Fixtures', () => {
  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let vat: Vat
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock
  let ilkJoin: Join
  let cdpProxy: CDPProxy
  let cdpProxyFromOther: CDPProxy

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
    env = await YieldEnvironment.setup(ownerAcc, otherAcc, [baseId, ilkId1, ilkId2], [seriesId])
    vat = env.vat
    cdpProxy = env.cdpProxy
  })

  // TODO: Do actual tests
  it('print', async () => {
    console.log(env)
  })
})
