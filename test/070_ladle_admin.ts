import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { BaseProvider } from '@ethersproject/providers'
import { id } from '@yield-protocol/utils'

import FYTokenArtifact from '../artifacts/contracts/FYToken.sol/FYToken.json'
import JoinArtifact from '../artifacts/contracts/Join.sol/Join.json'
import OracleMockArtifact from '../artifacts/contracts/mocks/OracleMock.sol/OracleMock.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import PoolMockArtifact from '../artifacts/contracts/mocks/PoolMock.sol/PoolMock.json'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { OracleMock } from '../typechain/OracleMock'
import { PoolMock } from '../typechain/PoolMock'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

import { YieldEnvironment, WAD, RAY } from './shared/fixtures'

describe('Ladle - admin', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let fyToken: FYToken
  let base: ERC20Mock
  let baseJoin: Join
  let ilk: ERC20Mock
  let ilkJoin: Join
  let pool: PoolMock
  let oracle: OracleMock
  let rateOracle: OracleMock
  let ladle: Ladle
  let ladleFromOther: Ladle

  const mockAssetId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockSeriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId], [])
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
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ratio = 10000 // == 100% collateralization ratio

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    baseJoin = env.joins.get(baseId) as Join
    rateOracle = env.oracles.get('rate') as OracleMock

    ladleFromOther = ladle.connect(otherAcc)

    // ==== Set testing environment ====
    ilk = (await deployContract(ownerAcc, ERC20MockArtifact, [ilkId, 'Mock Ilk'])) as ERC20Mock
    oracle = (await deployContract(ownerAcc, OracleMockArtifact, [])) as OracleMock
    await oracle.setSpot(RAY)

    await cauldron.addAsset(ilkId, ilk.address)
    await cauldron.setMaxDebt(baseId, ilkId, WAD.mul(2))
    await cauldron.setSpotOracle(baseId, ilkId, oracle.address, ratio)

    // Deploy a join
    ilkJoin = (await deployContract(ownerAcc, JoinArtifact, [ilk.address])) as Join
    await ilkJoin.grantRoles([id('join(address,int128)')], ladle.address)

    // Deploy a series
    const provider: BaseProvider = ethers.getDefaultProvider()
    const now = (await provider.getBlock(provider.getBlockNumber())).timestamp
    fyToken = (await deployContract(ownerAcc, FYTokenArtifact, [
      rateOracle.address,
      baseJoin.address,
      now + 3 * 30 * 24 * 60 * 60,
      seriesId,
      'Mock FYToken',
    ])) as FYToken
    await cauldron.addSeries(seriesId, baseId, fyToken.address)
    await cauldron.addIlks(seriesId, [ilkId])

    // Deploy a pool
    pool = (await deployContract(ownerAcc, PoolMockArtifact, [base.address, fyToken.address])) as PoolMock
  })

  describe('join admin', async () => {
    it('does not allow adding a join before adding its ilk', async () => {
      await expect(ladle.addJoin(mockAssetId, ilkJoin.address)).to.be.revertedWith('Asset not found')
    })

    it('adds a join', async () => {
      expect(await ladle.addJoin(ilkId, ilkJoin.address))
        .to.emit(ladle, 'JoinAdded')
        .withArgs(ilkId, ilkJoin.address)
      expect(await ladle.joins(ilkId)).to.equal(ilkJoin.address)
    })

    describe('with a join added', async () => {
      beforeEach(async () => {
        await ladle.addJoin(ilkId, ilkJoin.address)
      })

      it('only one join per asset', async () => {
        await expect(ladle.addJoin(ilkId, ilkJoin.address)).to.be.revertedWith('One Join per Asset')
      })
    })
  })

  describe('pool admin', async () => {
    it('does not allow adding a pool before adding its series', async () => {
      await expect(ladle.addPool(mockSeriesId, pool.address)).to.be.revertedWith('Series not found')
    })

    it('adds a pool', async () => {
      expect(await ladle.addPool(seriesId, pool.address))
        .to.emit(ladle, 'PoolAdded')
        .withArgs(seriesId, pool.address)
      expect(await ladle.pools(seriesId)).to.equal(pool.address)
    })

    describe('with a pool added', async () => {
      beforeEach(async () => {
        await ladle.addPool(seriesId, pool.address)
      })

      it('only one pool per asset', async () => {
        await expect(ladle.addPool(seriesId, pool.address)).to.be.revertedWith('One Pool per Series')
      })
    })
  })
})
