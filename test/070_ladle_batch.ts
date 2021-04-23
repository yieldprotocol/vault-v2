import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { constants, signatures } from '@yield-protocol/utils-v2'
const { WAD, MAX128 } = constants
const MAX = MAX128

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
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ethId = ethers.utils.formatBytes32String('ETH').slice(0, 14)
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const vaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12))
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

  it('builds a vault, permit and serve', async () => {
    const ilkSeparator = await ilk.DOMAIN_SEPARATOR()
    const deadline = MAX
    const posted = WAD.mul(2)
    const nonce = await ilk.nonces(owner)
    const approval = {
      owner: owner,
      spender: ilkJoin.address,
      value: posted,
    }
    const permitDigest = signatures.getPermitDigest(ilkSeparator, approval, nonce, deadline)
    const { v, r, s } = signatures.sign(permitDigest, signatures.privateKey0)

    const borrowed = WAD

    await ladle.batch(vaultId, [
      ladle.buildAction(seriesId, ilkId),
      ladle.forwardPermitAction(ilkId, true, ilkJoin.address, posted, deadline, v, r, s),
      ladle.serveAction(owner, posted, borrowed, MAX)
    ])

    const vault = await cauldron.vaults(vaultId)
    expect(vault.owner).to.equal(owner)
    expect(vault.seriesId).to.equal(seriesId)
    expect(vault.ilkId).to.equal(ilkId)
  })

  it('builds a vault, wraps ether and serve', async () => {
    const newVaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12))
    const posted = WAD.mul(2)
    const borrowed = WAD

    await ladle.batch(
      newVaultId,
      [
        ladle.buildAction(seriesId, ethId),
        ladle.joinEtherAction(ethId),
        ladle.serveAction(owner, posted, borrowed, MAX)
      ],
      { value: posted }
    )

    const vault = await cauldron.vaults(newVaultId)
    expect(vault.owner).to.equal(owner)
    expect(vault.seriesId).to.equal(seriesId)
    expect(vault.ilkId).to.equal(ethId)
  })

  it('users can transfer ETH then pour, then serve in a single transaction with multicall', async () => {
    const posted = WAD.mul(2)
    const borrowed = WAD

    await ladle.batch(
      ethVaultId,
      [
        ladle.joinEtherAction(ethId),
        ladle.pourAction(owner, posted, 0),
        ladle.serveAction(other, 0, borrowed, MAX)        
      ],
      { value: posted }
    )
  })

  it('calls can be routed to pools', async () => {
    await ladle.build(vaultId, seriesId, ilkId) // ladle.batch can only be executed by vault owners
    await base.mint(pool.address, WAD)

    const retrieveBaseTokenCall = pool.interface.encodeFunctionAction('retrieveBaseToken', [owner])
    await expect(await ladle.route(vaultId, retrieveBaseTokenCall)) // The pool is found through the vault seriesId
      .to.emit(base, 'Transfer')
      .withArgs(pool.address, owner, WAD)
  })
})
