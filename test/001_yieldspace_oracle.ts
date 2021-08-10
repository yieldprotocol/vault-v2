import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants, id } from '@yield-protocol/utils-v2'
const { WAD, MAX256 } = constants
const MAX = MAX256

import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import VaultMockArtifact from '../artifacts/contracts/mocks/VaultMock.sol/VaultMock.json'
import PoolMockArtifact from '../artifacts/contracts/mocks/PoolMock.sol/PoolMock.json'
import YieldSpaceOracleArtifact from '../artifacts/contracts/YieldSpaceOracle.sol/YieldSpaceOracle.json'

import { ERC20Mock as ERC20, ERC20Mock } from '../typechain/ERC20Mock'
import { Strategy } from '../typechain/Strategy'
import { VaultMock } from '../typechain/VaultMock'
import { PoolMock } from '../typechain/PoolMock'
import { FYTokenMock } from '../typechain/FYTokenMock'
import { YieldSpaceOracle } from '../typechain/YieldSpaceOracle'

import { BigNumber } from 'ethers'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

function almostEqual(x: BigNumber, y: BigNumber, p: BigNumber) {
  // Check that abs(x - y) < p:
  const diff = x.gt(y) ? BigNumber.from(x).sub(y) : BigNumber.from(y).sub(x) // Not sure why I have to convert x and y to BigNumber
  expect(diff.div(p)).to.eq(0) // Hack to avoid silly conversions. BigNumber truncates decimals off.
}

describe('Strategy - Pool Management', async function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string

  let vault: VaultMock
  let base: ERC20
  let fyToken: FYTokenMock
  let pool: PoolMock
  let oracle: YieldSpaceOracle

  let maturity = 1633046399

  let baseId: string
  let series1Id: string

  const ZERO_ADDRESS = '0x' + '0'.repeat(40)

  async function fixture() {} // For now we just use this to snapshot and revert the state of the blockchain

  before(async () => {
    await loadFixture(fixture) // This snapshots the blockchain as a side effect
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = ownerAcc.address
  })

  after(async () => {
    await loadFixture(fixture) // We advance the time to test maturity features, this rolls it back after the tests
  })

  beforeEach(async () => {
    // Set up Vault and Series
    vault = (await deployContract(ownerAcc, VaultMockArtifact, [])) as VaultMock
    base = ((await ethers.getContractAt('ERC20Mock', await vault.base(), ownerAcc)) as unknown) as ERC20Mock
    baseId = await vault.baseId()

    series1Id = await vault.callStatic.addSeries(maturity)
    await vault.addSeries(maturity)
    fyToken = ((await ethers.getContractAt(
      'FYTokenMock',
      (await vault.series(series1Id)).fyToken,
      ownerAcc
    )) as unknown) as FYTokenMock

    // Set up YieldSpace
    pool = (await deployContract(ownerAcc, PoolMockArtifact, [base.address, fyToken.address])) as PoolMock
    await base.mint(pool.address, WAD.mul(1000000))
    await fyToken.mint(pool.address, WAD.mul(100000))
    await pool.mint(owner, true, 0)
    await pool.sync()

    oracle = (await deployContract(ownerAcc, YieldSpaceOracleArtifact, [pool.address])) as YieldSpaceOracle
  })

  it('sets up testing environment', async () => {})

  it('updates the first time', async () => {
    await expect(oracle.update()).to.emit(oracle, 'Updated')
    expect(await oracle.twarTimestamp()).to.equal(await pool.lastCached())
    const spotRatio = WAD.mul(await base.balanceOf(pool.address)).div(await fyToken.balanceOf(pool.address))
    expect(await oracle.ratioCumulative()).to.equal(
      spotRatio.mul(await pool.lastCached())
    )
    expect(await oracle.twar()).to.equal(
      spotRatio
    )
  })

  describe('with an ongoing oracle', async () => {
    beforeEach(async () => {
      await oracle.update()
    })

    it('updates again, without changes to reserves', async () => {
      const spotRatio = WAD.mul(await base.balanceOf(pool.address)).div(await fyToken.balanceOf(pool.address))
      const lastCachedBefore = await pool.lastCached()
      const ratioCumulativeBefore = await oracle.ratioCumulative()
      const elapsed = 3600
      const snapshotId = await ethers.provider.send('evm_snapshot', [])
      await ethers.provider.send('evm_mine', [lastCachedBefore + elapsed])

      // Sync the pool to update pool.lastCached
      await pool.sync()

      await expect(oracle.update()).to.emit(oracle, 'Updated')
      expect(await oracle.twarTimestamp()).to.equal(await pool.lastCached())

      expect(await oracle.twar()).to.equal(
        spotRatio
      )

      expect(await oracle.ratioCumulative())
        .to.equal(ratioCumulativeBefore.add(spotRatio.mul(elapsed - 1)))

      await ethers.provider.send('evm_revert', [snapshotId])
    })

    it.only('updates again, with changes to reserves', async () => {
      console.log((WAD.mul(await base.balanceOf(pool.address)).div(await fyToken.balanceOf(pool.address))).toString())
      const lastCachedBefore = await pool.lastCached()
      const ratioCumulativeBefore = await oracle.ratioCumulative()
      const elapsed = 3600
      const snapshotId = await ethers.provider.send('evm_snapshot', [])
      await ethers.provider.send('evm_mine', [lastCachedBefore + elapsed])

      // Change the reserves and sync
      await fyToken.mint(pool.address, WAD.mul(100000))
      const spotRatioAfter = WAD.mul(await base.balanceOf(pool.address)).div(await fyToken.balanceOf(pool.address))
      await pool.sync()

      await expect(oracle.update()).to.emit(oracle, 'Updated')
      expect(await oracle.twarTimestamp()).to.equal(await pool.lastCached())

      almostEqual(
        await oracle.ratioCumulative(),
        ratioCumulativeBefore.add(spotRatioAfter.mul(elapsed)),
        WAD.mul(20) // 20 seconds up or down
      )

      console.log((await oracle.twar()).toString())
      console.log((WAD.mul(await base.balanceOf(pool.address)).div(await fyToken.balanceOf(pool.address))).toString())
      console.log(((await oracle.ratioCumulative()).sub(ratioCumulativeBefore)).div(elapsed).toString())
      almostEqual(
        await oracle.twar(),
        ((await oracle.ratioCumulative()).sub(ratioCumulativeBefore)).div(elapsed),
        BigNumber.from(1000000) // To a 0.0001%
      )

      await ethers.provider.send('evm_revert', [snapshotId])
    })
  })

  /* it('inits up', async () => {
    await base.mint(strategy.address, WAD)
    await expect(strategy.init(user1)).to.emit(strategy, 'Transfer')
    expect(await strategy.balanceOf(user1)).to.equal(WAD)
  })

  describe('once initialized', async () => {
    beforeEach(async () => {
      await base.mint(strategy.address, WAD)
      await strategy.init(owner)
    })

    it("can't initialize again", async () => {
      await base.mint(strategy.address, WAD)
      await expect(strategy.init(user1)).to.be.revertedWith('Already initialized')
    })

    it('the strategy value is the buffer value', async () => {
      await fyToken.mint(strategy.address, WAD) // <-- This should be ignored
      expect(await strategy.strategyValue()).to.equal(WAD)
    })

    it("can't set pools with mismatched seriesId", async () => {
      await expect(strategy.setPools([pool.address, pool2.address], [series1Id, series1Id])).to.be.revertedWith(
        'Mismatched seriesId'
      )
    })

    it('sets a pool queue', async () => {
      await expect(strategy.setPools([pool.address, pool2.address], [series1Id, series2Id])).to.emit(
        strategy,
        'PoolsSet'
      )

      expect(await strategy.poolCounter()).to.equal(MAX)
      expect(await strategy.pools(0)).to.equal(pool.address)
      expect(await strategy.pools(1)).to.equal(pool2.address)
      expect(await strategy.seriesIds(0)).to.equal(series1Id)
      expect(await strategy.seriesIds(1)).to.equal(series2Id)
    })

    describe('with a pool queue set', async () => {
      beforeEach(async () => {
        await strategy.setPools([pool.address, pool2.address], [series1Id, series2Id])
      })

      it("can't set a new pool queue until done", async () => {
        await expect(strategy.setPools([pool.address, pool2.address], [series1Id, series1Id])).to.be.revertedWith(
          'Pools still queued'
        )
      })

      it('swaps to the first pool', async () => {
        await expect(strategy.swap()).to.emit(strategy, 'PoolSwapped')

        expect(await strategy.poolCounter()).to.equal(0)
        expect(await strategy.pool()).to.equal(pool.address)
        expect(await strategy.fyToken()).to.equal(fyToken.address)

        const vaultId = await strategy.vaultId()
        const [vaultOwner, vaultSeriesId] = await vault.vaults(vaultId)
        expect(vaultOwner).to.equal(strategy.address)
        expect(vaultSeriesId).to.equal(series1Id)

        const poolCache = await strategy.poolCache()
        expect(poolCache.base).to.equal(await pool.baseCached())
        expect(poolCache.fyToken).to.equal(await pool.fyTokenCached())
      })

      describe('with an active pool', async () => {
        beforeEach(async () => {
          await strategy.swap()
        })

        it("can't swap to a new pool queue until maturity", async () => {
          await expect(strategy.swap()).to.be.revertedWith('Only after maturity')
        })

        it('can swap to the next pool after maturity', async () => {
          const snapshotId = await ethers.provider.send('evm_snapshot', [])
          await ethers.provider.send('evm_mine', [maturity + 1])

          await expect(strategy.swap()).to.emit(strategy, 'PoolSwapped')

          expect(await strategy.poolCounter()).to.equal(1)
          expect(await strategy.pool()).to.equal(pool2.address)
          expect(await strategy.fyToken()).to.equal(fyToken2.address)

          const vaultId = await strategy.vaultId()
          const [vaultOwner, vaultSeriesId] = await vault.vaults(vaultId)
          expect(vaultOwner).to.equal(strategy.address)
          expect(vaultSeriesId).to.equal(series2Id)

          const poolCache = await strategy.poolCache()
          expect(poolCache.base).to.equal(await pool2.baseCached())
          expect(poolCache.fyToken).to.equal(await pool2.fyTokenCached())

          await ethers.provider.send('evm_revert', [snapshotId])
        })

        it('can swap out of the last pool', async () => {
          const snapshotId = await ethers.provider.send('evm_snapshot', [])
          await ethers.provider.send('evm_mine', [maturity2 + 1])

          await strategy.swap() // Swap to next pool
          await expect(strategy.swap()).to.emit(strategy, 'PoolSwapped') // Swap out of next pool

          expect(await strategy.poolCounter()).to.equal(MAX)
          expect(await strategy.pool()).to.equal(ZERO_ADDRESS)
          expect(await strategy.fyToken()).to.equal(ZERO_ADDRESS)
          expect(await strategy.vaultId()).to.equal('0x' + '00'.repeat(12))

          const poolCache = await strategy.poolCache()
          expect(poolCache.base).to.equal(ZERO_ADDRESS)
          expect(poolCache.fyToken).to.equal(ZERO_ADDRESS)

          await ethers.provider.send('evm_revert', [snapshotId])
        })

        it('fyToken are counted towards the strategy value', async () => {
          await fyToken.mint(strategy.address, WAD)
          expect(await strategy.strategyValue()).to.equal(WAD.mul(2))
        })

        it('LP tokens are counted towards the strategy value', async () => {
          await pool.transfer(strategy.address, WAD)
          expect(await strategy.strategyValue()).to.equal(
            WAD.add(
              (await base.balanceOf(pool.address))
                .add(await fyToken.balanceOf(pool.address))
                .mul(await pool.balanceOf(strategy.address))
                .div(await pool.totalSupply())
            )
          )
        })
      })
    })
  }) */
})
