import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { WAD, MAX128 as MAX } from './shared/constants'

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
  let pool: PoolMock
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

  const OPS = {
    BUILD: 0,
    STIR_TO: 1,
    STIR_FROM: 2,
    POUR: 3,
    SERVE: 4,
    CLOSE: 5,
    REPAY: 6,
    REPAY_VAULT: 7,
    FORWARD_PERMIT: 8,
    FORWARD_DAI_PERMIT: 9,
    JOIN_ETHER: 10,
    EXIT_ETHER: 11,
    ROUTE: 12,
  }

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken
    pool = env.pools.get(seriesId) as PoolMock

    wethJoin = env.joins.get(ethId) as Join
    weth = (await ethers.getContractAt('WETH9Mock', await wethJoin.asset())) as WETH9Mock

    ethVaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ethId) as string
  })

  it('builds a vault and posts to it', async () => {
    const buildData = ethers.utils.defaultAbiCoder.encode(['bytes6', 'bytes6'], [seriesId, ilkId])
    const pourData = ethers.utils.defaultAbiCoder.encode(['address', 'int128', 'int128'], [owner, WAD, WAD])
    await ladle.batch(vaultId, [OPS.BUILD, OPS.POUR], [buildData, pourData])

    const vault = await cauldron.vaults(vaultId)
    expect(vault.owner).to.equal(owner)
    expect(vault.seriesId).to.equal(seriesId)
    expect(vault.ilkId).to.equal(ilkId)

    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
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

    await ladle.multicall([buildBatchCall, pourBatchCall], true)

    expect(await fyToken.balanceOf(owner)).to.equal(WAD)
  })
})
