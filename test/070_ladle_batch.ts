import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { signatures } from '@yield-protocol/utils'
import { constants } from '@yield-protocol/utils-v2'
const { WAD, MAX128 } = constants
const MAX = MAX128

import { OPS } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { Ladle } from '../typechain/Ladle'
import { FYToken } from '../typechain/FYToken'
import { PoolMock } from '../typechain/PoolMock'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { WETH9Mock } from '../typechain/WETH9Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'

describe('Ladle - batch', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let ladle: Ladle
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
    const buildData = ethers.utils.defaultAbiCoder.encode(['bytes6', 'bytes6'], [seriesId, ilkId])

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
    const permitData = ethers.utils.defaultAbiCoder.encode(
      ['bytes6', 'bool', 'address', 'uint256', 'uint256', 'uint8', 'bytes32', 'bytes32'],
      [ilkId, true, ilkJoin.address, posted, deadline, v, r, s]
    )

    const borrowed = WAD
    const serveData = ethers.utils.defaultAbiCoder.encode(
      ['address', 'uint128', 'uint128', 'uint128'],
      [owner, posted, borrowed, MAX]
    )
    await ladle.batch(vaultId, [OPS.BUILD, OPS.FORWARD_PERMIT, OPS.SERVE], [buildData, permitData, serveData])

    const vault = await cauldron.vaults(vaultId)
    expect(vault.owner).to.equal(owner)
    expect(vault.seriesId).to.equal(seriesId)
    expect(vault.ilkId).to.equal(ilkId)
  })

  it('builds a vault, wraps ether and serve', async () => {
    const newVaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12))
    const posted = WAD.mul(2)
    const borrowed = WAD

    const buildData = ethers.utils.defaultAbiCoder.encode(['bytes6', 'bytes6'], [seriesId, ethId])
    const joinEtherData = ethers.utils.defaultAbiCoder.encode(['bytes6'], [ethId])
    const serveData = ethers.utils.defaultAbiCoder.encode(
      ['address', 'uint128', 'uint128', 'uint128'],
      [owner, posted, borrowed, MAX]
    )
    await ladle.batch(newVaultId, [OPS.BUILD, OPS.JOIN_ETHER, OPS.SERVE], [buildData, joinEtherData, serveData], {
      value: posted,
    })

    const vault = await cauldron.vaults(newVaultId)
    expect(vault.owner).to.equal(owner)
    expect(vault.seriesId).to.equal(seriesId)
    expect(vault.ilkId).to.equal(ethId)
  })

  it('users can transfer ETH then pour, then serve in a single transaction with multicall', async () => {
    const posted = WAD.mul(2)
    const borrowed = WAD

    const joinEtherData = ethers.utils.defaultAbiCoder.encode(['bytes6'], [ethId])
    const pourData = ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'int128'], [owner, posted, 0])
    const serveData = ethers.utils.defaultAbiCoder.encode(
      ['address', 'uint128', 'uint128', 'uint128'],
      [other, 0, borrowed, MAX]
    )
    await ladle.batch(ethVaultId, [OPS.JOIN_ETHER, OPS.POUR, OPS.SERVE], [joinEtherData, pourData, serveData], {
      value: posted,
    })
  })

  it('batches can be grouped with multicall', async () => {
    const buildData = ethers.utils.defaultAbiCoder.encode(['bytes6', 'bytes6'], [seriesId, ilkId])
    const pourData = ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'int128'], [owner, WAD, WAD])

    const buildBatchCall = ladle.interface.encodeFunctionData('batch', [vaultId, [OPS.BUILD], [buildData]])
    const pourBatchCall = ladle.interface.encodeFunctionData('batch', [vaultId, [OPS.POUR], [pourData]])

    await ladle.multicall([buildBatchCall, pourBatchCall])

    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
  })
})
