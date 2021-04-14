import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id } from '@yield-protocol/utils'

import CauldronArtifact from '../artifacts/contracts/Cauldron.sol/Cauldron.json'
import JoinArtifact from '../artifacts/contracts/Join.sol/Join.json'
import FYTokenArtifact from '../artifacts/contracts/FYToken.sol/FYToken.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import OracleMockArtifact from '../artifacts/contracts/mocks/OracleMock.sol/OracleMock.json'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { OracleMock } from '../typechain/OracleMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract } = waffle

describe('Cauldron - admin', function () {
  this.timeout(0)

  let ownerAcc: SignerWithAddress
  let owner: string
  let cauldron: Cauldron
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk1: ERC20Mock
  let ilk2: ERC20Mock
  let join: Join
  let oracle: OracleMock

  const mockAssetId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockSeriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockAddress = ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))
  const emptyAddress = ethers.utils.getAddress('0x0000000000000000000000000000000000000000')

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId1 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const otherIlk1 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId2 = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const maturity = 1640995199
  const ratio = 1000000 // == 100% collateralization ratio

  beforeEach(async () => {
    cauldron = (await deployContract(ownerAcc, CauldronArtifact, [])) as Cauldron
    base = (await deployContract(ownerAcc, ERC20MockArtifact, [baseId, 'Mock Base'])) as ERC20Mock
    ilk1 = (await deployContract(ownerAcc, ERC20MockArtifact, [ilkId1, 'Mock Ilk'])) as ERC20Mock
    ilk2 = (await deployContract(ownerAcc, ERC20MockArtifact, [ilkId2, 'Mock Ilk'])) as ERC20Mock
    join = (await deployContract(ownerAcc, JoinArtifact, [base.address])) as Join
    fyToken = (await deployContract(ownerAcc, FYTokenArtifact, [
      base.address,
      join.address,
      maturity,
      seriesId,
      'Mock FYToken',
    ])) as FYToken
    oracle = (await deployContract(ownerAcc, OracleMockArtifact, [])) as OracleMock

    await cauldron.grantRoles(
      [
        id('addAsset(bytes6,address)'),
        id('setMaxDebt(bytes6,bytes6,uint128)'),
        id('setRateOracle(bytes6,address,bytes)'),
        id('setSpotOracle(bytes6,bytes6,address,uint32,bytes)'),
        id('addSeries(bytes6,bytes6,address)'),
        id('addIlks(bytes6,bytes6[])'),
      ],
      owner
    )
  })

  it('adds an asset', async () => {
    expect(await cauldron.addAsset(ilkId1, ilk1.address))
      .to.emit(cauldron, 'AssetAdded')
      .withArgs(ilkId1, ilk1.address)
    expect(await cauldron.assets(ilkId1)).to.equal(ilk1.address)
  })

  it('does not allow adding a series before adding its base', async () => {
    await expect(cauldron.addSeries(seriesId, baseId, fyToken.address)).to.be.revertedWith('Asset not found')
  })

  describe('with a base and an ilk added', async () => {
    beforeEach(async () => {
      await cauldron.addAsset(baseId, base.address)
      await cauldron.addAsset(ilkId1, ilk1.address)
      await cauldron.addAsset(ilkId2, ilk2.address)
    })

    it('does not allow using the same asset identifier twice', async () => {
      await expect(cauldron.addAsset(baseId, base.address)).to.be.revertedWith('Id already used')
    })

    it('allows adding the same asset again with a different identifier', async () => {
      expect(await cauldron.addAsset(otherIlk1, ilk1.address))
        .to.emit(cauldron, 'AssetAdded')
        .withArgs(otherIlk1, ilk1.address)
      expect(await cauldron.assets(otherIlk1)).to.equal(ilk1.address)
    })

    it('does not allow setting a debt limit for an unknown base', async () => {
      await expect(cauldron.setMaxDebt(mockAssetId, ilkId1, 2)).to.be.revertedWith('Asset not found')
    })

    it('does not allow setting a debt limit for an unknown ilk', async () => {
      await expect(cauldron.setMaxDebt(baseId, mockAssetId, 2)).to.be.revertedWith('Asset not found')
    })

    it('sets a debt limit', async () => {
      expect(await cauldron.setMaxDebt(baseId, ilkId1, 2))
        .to.emit(cauldron, 'MaxDebtSet')
        .withArgs(baseId, ilkId1, 2)

      const debt = await cauldron.debt(baseId, ilkId1)
      expect(debt.max).to.equal(2)
    })

    it('does not allow adding a rate oracle for an unknown base', async () => {
      await expect(cauldron.setRateOracle(mockAssetId, oracle.address, '0x00')).to.be.revertedWith('Asset not found')
    })

    it('adds a rate oracle', async () => {
      expect(await cauldron.setRateOracle(baseId, oracle.address, '0x00'))
        .to.emit(cauldron, 'RateOracleAdded')
        .withArgs(baseId, oracle.address, '0x00')

      expect(await cauldron.rateOracles(baseId)).to.equal(oracle.address)
    })

    it('does not allow adding a series without a rate oracle for its base', async () => {
      await expect(cauldron.addSeries(seriesId, baseId, fyToken.address)).to.be.revertedWith('Rate oracle not found')
    })

    describe('with a rate oracle added', async () => {
      beforeEach(async () => {
        await cauldron.setRateOracle(baseId, oracle.address, '0x00')
      })

      it('does not allow not linking a series to a fyToken', async () => {
        await expect(cauldron.addSeries(seriesId, baseId, emptyAddress)).to.be.revertedWith('Series need a fyToken')
      })

      it('does not allow linking a series to the wrong base', async () => {
        await expect(cauldron.addSeries(seriesId, ilkId1, fyToken.address)).to.be.revertedWith(
          'Mismatched series and base'
        )
      })

      it('adds a series', async () => {
        expect(await cauldron.addSeries(seriesId, baseId, fyToken.address))
          .to.emit(cauldron, 'SeriesAdded')
          .withArgs(seriesId, baseId, fyToken.address)

        const series = await cauldron.series(seriesId)
        expect(series.fyToken).to.equal(fyToken.address)
        expect(series.baseId).to.equal(baseId)
        expect(series.maturity).to.equal(maturity)
      })

      describe('with a series added', async () => {
        beforeEach(async () => {
          await cauldron.addSeries(seriesId, baseId, fyToken.address)
        })

        it('does not allow using the same series identifier twice', async () => {
          await expect(cauldron.addSeries(seriesId, baseId, fyToken.address)).to.be.revertedWith('Id already used')
        })

        it('does not allow adding a spot oracle for an unknown base', async () => {
          await expect(cauldron.setSpotOracle(mockAssetId, ilkId1, oracle.address, ratio, '0x00')).to.be.revertedWith(
            'Asset not found'
          )
        })

        it('does not allow adding a spot oracle for an unknown ilk', async () => {
          await expect(cauldron.setSpotOracle(baseId, mockAssetId, oracle.address, ratio, '0x00')).to.be.revertedWith(
            'Asset not found'
          )
        })

        it('adds a spot oracle and its collateralization ratio', async () => {
          expect(await cauldron.setSpotOracle(baseId, ilkId1, oracle.address, ratio, '0x00'))
            .to.emit(cauldron, 'SpotOracleAdded')
            .withArgs(baseId, ilkId1, oracle.address, ratio, '0x00')

          const spot = await cauldron.spotOracles(baseId, ilkId1)
          expect(spot.oracle).to.equal(oracle.address)
          expect(spot.ratio).to.equal(ratio)
        })

        describe('with an oracle for the series base and an ilk', async () => {
          beforeEach(async () => {
            await cauldron.setSpotOracle(baseId, ilkId1, oracle.address, ratio, '0x00')
            await cauldron.setSpotOracle(baseId, ilkId2, oracle.address, ratio, '0x00')
          })

          it("does not allow adding an asset as an ilk to a series that doesn't exist", async () => {
            await expect(cauldron.addIlks(mockSeriesId, [ilkId1])).to.be.revertedWith('Series not found')
          })

          it('does not allow adding an asset as an ilk without an oracle for a series base', async () => {
            await expect(cauldron.addIlks(seriesId, [mockAssetId])).to.be.revertedWith('Spot oracle not found')
          })

          it('adds assets as ilks to a series', async () => {
            expect(await cauldron.addIlks(seriesId, [ilkId1, ilkId2]))
              .to.emit(cauldron, 'IlkAdded')
              .withArgs(seriesId, ilkId1)
              .to.emit(cauldron, 'IlkAdded')
              .withArgs(seriesId, ilkId2)

            expect(await cauldron.ilks(seriesId, ilkId1)).to.be.true
            expect(await cauldron.ilks(seriesId, ilkId2)).to.be.true
          })
        })
      })
    })
  })
})
