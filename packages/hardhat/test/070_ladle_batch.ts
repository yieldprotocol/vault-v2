import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { constants, signatures } from '@yield-protocol/utils-v2'
const { WAD, MAX128 } = constants
const MAX = MAX128
import { ETH } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { PoolMock } from '../typechain/PoolMock'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { WETH9Mock } from '../typechain/WETH9Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'
import { getLastVaultId } from '../src/helpers'

describe('Ladle - batch', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let ladle: LadleWrapper
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock
  let pool: PoolMock
  let ilkJoin: Join
  let wethJoin: Join
  let weth: WETH9Mock

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId, otherIlkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ETH
  const otherIlkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ethId = ETH
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const cachedVaultId = '0x' + '00'.repeat(12)
  let ethVaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken
    pool = env.pools.get(seriesId) as PoolMock

    ilkJoin = env.joins.get(ilkId) as Join

    wethJoin = env.joins.get(ethId) as Join
    weth = (await ethers.getContractAt('WETH9Mock', await wethJoin.asset())) as WETH9Mock

    ethVaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ethId) as string
  })

  it('builds a vault, tweaks it and gives it', async () => {
    await ladle.batch([
      ladle.buildAction(seriesId, ilkId),
      ladle.tweakAction(cachedVaultId, seriesId, otherIlkId),
      ladle.giveAction(cachedVaultId, other),
    ])
  })

  it('builds two vaults and gives them', async () => {
    await ladle.batch([
      ladle.buildAction(seriesId, ilkId),
      ladle.giveAction(cachedVaultId, other),
      ladle.buildAction(seriesId, ilkId),
      ladle.giveAction(cachedVaultId, other),
    ])
  })

  it('builds a vault and destroys it', async () => {
    await ladle.batch([ladle.buildAction(seriesId, ilkId), ladle.destroyAction(cachedVaultId)])
  })

  it("after giving a vault, it can't tweak it", async () => {
    await expect(
      ladle.batch([
        ladle.buildAction(seriesId, ilkId),
        ladle.giveAction(cachedVaultId, other),
        ladle.tweakAction(cachedVaultId, seriesId, otherIlkId),
      ])
    ).to.be.revertedWith('Only vault owner')
  })

  /* it('builds a vault, permit and pour', async () => {
    const ilkSeparator = await ilk.DOMAIN_SEPARATOR()
    const deadline = MAX
    const posted = WAD.mul(4)
    const nonce = await ilk.nonces(owner)
    const approval = {
      owner: owner,
      spender: ilkJoin.address,
      value: posted,
    }
    const permitDigest = signatures.getPermitDigest(ilkSeparator, approval, nonce, deadline)
    const { v, r, s } = signatures.sign(permitDigest, signatures.privateKey0)

    const borrowed = WAD

    await ladle.batch([
      ladle.buildAction(seriesId, ilkId),
      ladle.forwardPermitAction(ilk.address, ilkJoin.address, posted, deadline, v, r, s),
      ladle.pourAction(cachedVaultId, owner, posted, borrowed),
    ])

    const vault = await cauldron.vaults(await getLastVaultId(cauldron))
    expect(vault.owner).to.equal(owner)
    expect(vault.seriesId).to.equal(seriesId)
    expect(vault.ilkId).to.equal(ilkId)
  }) */

  it('builds a vault, wraps ether and serve', async () => {
    const posted = WAD.mul(2)
    const borrowed = WAD

    await ladle.batch(
      [
        ladle.buildAction(seriesId, ethId),
        ladle.joinEtherAction(ethId),
        ladle.serveAction(cachedVaultId, owner, posted, borrowed, MAX),
      ],
      { value: posted }
    )

    const vault = await cauldron.vaults(await getLastVaultId(cauldron))
    expect(vault.owner).to.equal(owner)
    expect(vault.seriesId).to.equal(seriesId)
    expect(vault.ilkId).to.equal(ethId)
  })

  it('users can transfer ETH then pour, then serve', async () => {
    const posted = WAD.mul(2)
    const borrowed = WAD

    await ladle.batch(
      [
        ladle.joinEtherAction(ethId),
        ladle.pourAction(ethVaultId, owner, posted, 0),
        ladle.serveAction(ethVaultId, other, 0, borrowed, MAX),
      ],
      { value: posted }
    )
  })

  it('users can transfer ETH then pour, then close', async () => {
    const posted = WAD.mul(4)
    const borrowed = WAD.mul(2)

    await ladle.batch(
      [
        ladle.joinEtherAction(ethId),
        ladle.pourAction(ethVaultId, owner, posted, borrowed),
        ladle.closeAction(ethVaultId, other, 0, borrowed.div(2).mul(-1)),
      ],
      { value: posted }
    )
  })

  it('users can transfer to a pool and repay in a batch', async () => {
    const separator = await base.DOMAIN_SEPARATOR()
    const deadline = MAX
    const amount = WAD
    const nonce = await base.nonces(owner)
    const approval = {
      owner: owner,
      spender: ladle.address,
      value: amount,
    }
    const permitDigest = signatures.getPermitDigest(separator, approval, nonce, deadline)

    const { v, r, s } = signatures.sign(permitDigest, signatures.privateKey0)

    const posted = WAD.mul(8)
    const borrowed = WAD.mul(4)

    await ladle.batch([
      ladle.buildAction(seriesId, ilkId),
      ladle.pourAction(cachedVaultId, owner, posted, borrowed),
      ladle.forwardPermitAction(base.address, ladle.address, amount, deadline, v, r, s),
      ladle.transferAction(base.address, pool.address, WAD),
      ladle.repayAction(cachedVaultId, other, 0, 0),
    ])
  })

  it('users can transfer to a pool and repay a whole vault in a batch', async () => {
    const separator = await base.DOMAIN_SEPARATOR()
    const deadline = MAX
    const amount = WAD
    const nonce = await base.nonces(owner)
    const approval = {
      owner: owner,
      spender: ladle.address,
      value: amount,
    }
    const permitDigest = signatures.getPermitDigest(separator, approval, nonce, deadline)

    const { v, r, s } = signatures.sign(permitDigest, signatures.privateKey0)

    const posted = WAD.mul(2)
    const borrowed = WAD

    await ladle.batch([
      ladle.buildAction(seriesId, ilkId),
      ladle.pourAction(cachedVaultId, owner, posted, borrowed),
      ladle.forwardPermitAction(base.address, ladle.address, amount, deadline, v, r, s),
      ladle.transferAction(base.address, pool.address, WAD),
      ladle.repayVaultAction(cachedVaultId, other, 0, MAX),
    ])
  })

  it('calls can be routed to pools', async () => {
    await base.mint(pool.address, WAD)

    const retrieveBaseCall = pool.interface.encodeFunctionData('retrieveBase', [owner])
    await expect(await ladle.route(pool.address, retrieveBaseCall))
      .to.emit(base, 'Transfer')
      .withArgs(pool.address, owner, WAD)
  })

  it('errors bubble up from calls routed to pools', async () => {
    await base.mint(pool.address, WAD)

    const sellBaseCall = pool.interface.encodeFunctionData('sellBase', [owner, MAX128])
    await expect(ladle.route(pool.address, sellBaseCall)).to.be.revertedWith('Pool: Not enough fyToken obtained')
  })

  it('sells base', async () => {
    await base.mint(pool.address, WAD)

    await expect(await ladle.sellBase(pool.address, owner, 0)).to.emit(pool, 'Trade')
  })

  it('sells fyToken', async () => {
    await fyToken.mint(pool.address, WAD)

    await expect(await ladle.sellFYToken(pool.address, owner, 0)).to.emit(pool, 'Trade')
  })
})
