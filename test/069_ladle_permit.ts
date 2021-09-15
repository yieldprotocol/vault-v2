import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { constants, signatures } from '@yield-protocol/utils-v2'
const { WAD, MAX256 } = constants
const MAX = MAX256
import { DAI } from '../src/constants'

import { Join } from '../typechain/Join'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { DAIMock } from '../typechain/DAIMock'
import { FYToken } from '../typechain/FYToken'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'

describe('Ladle - permit', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let ilk: ERC20Mock
  let ilkJoin: Join
  let dai: DAIMock
  let fyToken: FYToken
  let ladle: LadleWrapper

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId, DAI], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockIlkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  let ilkVaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    ladle = env.ladle
    ilkJoin = env.joins.get(ilkId) as Join
    ilk = env.assets.get(ilkId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken
    dai = (env.assets.get(DAI) as unknown) as DAIMock

    ilkVaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
  })

  it('users can use the ladle to execute permit on an asset', async () => {
    const ilkSeparator = await ilk.DOMAIN_SEPARATOR()
    const deadline = MAX
    const amount = WAD
    const nonce = await ilk.nonces(owner)
    const approval = {
      owner: owner,
      spender: ilkJoin.address,
      value: amount,
    }
    const permitDigest = signatures.getPermitDigest(ilkSeparator, approval, nonce, deadline)

    const { v, r, s } = signatures.sign(permitDigest, signatures.privateKey0)

    expect(await ladle.forwardPermit(ilk.address, ilkJoin.address, amount, deadline, v, r, s))
      .to.emit(ilk, 'Approval')
      .withArgs(owner, ilkJoin.address, WAD)

    expect(await ilk.allowance(owner, ilkJoin.address)).to.equal(WAD)
  })

  it('users can use the ladle to execute permit on a fyToken', async () => {
    const fyTokenSeparator = await fyToken.DOMAIN_SEPARATOR()
    const deadline = MAX
    const amount = WAD
    const nonce = await fyToken.nonces(owner)
    const approval = {
      owner: owner,
      spender: ladle.address,
      value: amount,
    }
    const permitDigest = signatures.getPermitDigest(fyTokenSeparator, approval, nonce, deadline)

    const { v, r, s } = signatures.sign(permitDigest, signatures.privateKey0)

    expect(await ladle.forwardPermit(fyToken.address, ladle.address, amount, deadline, v, r, s))
      .to.emit(fyToken, 'Approval')
      .withArgs(owner, ladle.address, WAD)

    expect(await fyToken.allowance(owner, ladle.address)).to.equal(WAD)
  })

  it('users can use the ladle to execute permit on a fyToken as a batch', async () => {
    const fyTokenSeparator = await fyToken.DOMAIN_SEPARATOR()
    const deadline = MAX
    const amount = WAD
    const nonce = await fyToken.nonces(owner)
    const approval = {
      owner: owner,
      spender: ladle.address,
      value: amount,
    }
    const permitDigest = signatures.getPermitDigest(fyTokenSeparator, approval, nonce, deadline)

    const { v, r, s } = signatures.sign(permitDigest, signatures.privateKey0)

    const vaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12)) // You can't use `batch` without owning or building a vault.

    expect(
      await ladle.batch([
        ladle.buildAction(seriesId, ilkId),
        ladle.forwardPermitAction(fyToken.address, ladle.address, amount, deadline, v, r, s),
      ])
    )
      .to.emit(fyToken, 'Approval')
      .withArgs(owner, ladle.address, WAD)

    expect(await fyToken.allowance(owner, ladle.address)).to.equal(WAD)
  })

  it('users can use the ladle to execute a dai-style permit on an asset', async () => {
    const daiSeparator = await dai.DOMAIN_SEPARATOR()
    const deadline = MAX
    const nonce = await fyToken.nonces(owner)
    const approval = {
      owner: owner,
      spender: ladle.address,
      can: true,
    }
    const daiPermitDigest = signatures.getDaiDigest(daiSeparator, approval, nonce, deadline)

    const { v, r, s } = signatures.sign(daiPermitDigest, signatures.privateKey0)

    expect(await ladle.forwardDaiPermit(dai.address, ladle.address, nonce, deadline, true, v, r, s))
      .to.emit(dai, 'Approval')
      .withArgs(owner, ladle.address, MAX)

    expect(await dai.allowance(owner, ladle.address)).to.equal(MAX)
  })

  it('users can use the ladle to execute a dai-style permit on an asset as a batch', async () => {
    const daiSeparator = await dai.DOMAIN_SEPARATOR()
    const deadline = MAX
    const nonce = await fyToken.nonces(owner)
    const approval = {
      owner: owner,
      spender: ladle.address,
      can: true,
    }
    const daiPermitDigest = signatures.getDaiDigest(daiSeparator, approval, nonce, deadline)

    const { v, r, s } = signatures.sign(daiPermitDigest, signatures.privateKey0)

    const vaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12)) // You can't use `batch` without owning or building a vault.

    expect(
      await ladle.batch([
        ladle.buildAction(seriesId, ilkId),
        ladle.forwardDaiPermitAction(dai.address, ladle.address, nonce, deadline, true, v, r, s),
      ])
    )
      .to.emit(dai, 'Approval')
      .withArgs(owner, ladle.address, MAX)

    expect(await dai.allowance(owner, ladle.address)).to.equal(MAX)
  })

  it("users can't use the ladle to execute permit on unregistered tokens", async () => {
    const ilkSeparator = await ilk.DOMAIN_SEPARATOR()
    const deadline = MAX
    const amount = WAD
    const nonce = await ilk.nonces(owner)
    const approval = {
      owner: owner,
      spender: ilkJoin.address,
      value: amount,
    }
    const permitDigest = signatures.getPermitDigest(ilkSeparator, approval, nonce, deadline)

    const { v, r, s } = signatures.sign(permitDigest, signatures.privateKey0)

    await expect(ladle.forwardPermit(owner, ilkJoin.address, amount, deadline, v, r, s)).to.be.revertedWith(
      'Unknown token'
    )
  })
})
