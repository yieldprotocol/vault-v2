import { id } from '@yield-protocol/utils-v2'

import { sendStatic } from './shared/helpers'

import { Contract } from '@ethersproject/contracts'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import CauldronArtifact from '../artifacts/contracts/Cauldron.sol/Cauldron.json'
import JoinFactoryArtifact from '../artifacts/contracts/JoinFactory.sol/JoinFactory.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import OracleMockArtifact from '../artifacts/contracts/mocks/oracles/OracleMock.sol/OracleMock.json'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { JoinFactory } from '../typechain/JoinFactory'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { OracleMock } from '../typechain/OracleMock'
import { SafeERC20Namer } from '../typechain/SafeERC20Namer'

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
  let joinFactory: JoinFactory
  let oracle: OracleMock

  const mockAssetId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockSeriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
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
    joinFactory = (await deployContract(ownerAcc, JoinFactoryArtifact, [])) as JoinFactory
    await joinFactory.grantRoles([id(joinFactory.interface, 'createJoin(address)')], owner)

    join = (await ethers.getContractAt(
      'Join',
      await sendStatic(joinFactory as Contract, 'createJoin', ownerAcc, [base.address]),
      ownerAcc
    )) as Join

    const SafeERC20NamerFactory = await ethers.getContractFactory('SafeERC20Namer')
    const safeERC20NamerLibrary = ((await SafeERC20NamerFactory.deploy()) as unknown) as SafeERC20Namer
    await safeERC20NamerLibrary.deployed()

    const fyTokenFactory = await ethers.getContractFactory('FYToken', {
      libraries: {
        SafeERC20Namer: safeERC20NamerLibrary.address,
      },
    })
    fyToken = ((await fyTokenFactory.deploy(
      baseId,
      base.address,
      join.address,
      maturity,
      seriesId,
      'Mock FYToken'
    )) as unknown) as FYToken
    await fyToken.deployed()

    oracle = (await deployContract(ownerAcc, OracleMockArtifact, [])) as OracleMock

    await cauldron.grantRoles(
      [
        id(cauldron.interface, 'addAsset(bytes6,address)'),
        id(cauldron.interface, 'setDebtLimits(bytes6,bytes6,uint96,uint24,uint8)'),
        id(cauldron.interface, 'setLendingOracle(bytes6,address)'),
        id(cauldron.interface, 'setSpotOracle(bytes6,bytes6,address,uint32)'),
        id(cauldron.interface, 'addSeries(bytes6,bytes6,address)'),
        id(cauldron.interface, 'addIlks(bytes6,bytes6[])'),
      ],
      owner
    )
  })

  it('does not allow using zero as an asset identifier', async () => {
    await expect(cauldron.addAsset('0x000000000000', base.address)).to.be.revertedWith('Asset id is zero')
  })

  it('adds an asset', async () => {
    expect(await cauldron.addAsset(ilkId1, ilk1.address))
      .to.emit(cauldron, 'AssetAdded')
      .withArgs(ilkId1, ilk1.address)
    expect(await cauldron.assets(ilkId1)).to.equal(ilk1.address)
  })

  it('does not allow adding a series before adding its base', async () => {
    await expect(cauldron.addSeries(seriesId, baseId, fyToken.address)).to.be.revertedWith('Base not found')
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

    it('does not allow setting debt limits for an unknown base', async () => {
      await expect(cauldron.setDebtLimits(mockAssetId, ilkId1, 0, 0, 0)).to.be.revertedWith('Base not found')
    })

    it('does not allow setting a debt limits for an unknown ilk', async () => {
      await expect(cauldron.setDebtLimits(baseId, mockAssetId, 0, 0, 0)).to.be.revertedWith('Ilk not found')
    })

    it('sets debt limits', async () => {
      expect(await cauldron.setDebtLimits(baseId, ilkId1, 2, 1, 3))
        .to.emit(cauldron, 'DebtLimitsSet')
        .withArgs(baseId, ilkId1, 2, 1, 3)

      const debt = await cauldron.debt(baseId, ilkId1)
      expect(debt.max).to.equal(2)
      expect(debt.min).to.equal(1)
      expect(debt.dec).to.equal(3)
    })

    it('does not allow adding a rate oracle for an unknown base', async () => {
      await expect(cauldron.setLendingOracle(mockAssetId, oracle.address)).to.be.revertedWith('Base not found')
    })

    it('adds a rate oracle', async () => {
      expect(await cauldron.setLendingOracle(baseId, oracle.address))
        .to.emit(cauldron, 'RateOracleAdded')
        .withArgs(baseId, oracle.address)

      expect(await cauldron.lendingOracles(baseId)).to.equal(oracle.address)
    })

    it('does not allow adding a series without a rate oracle for its base', async () => {
      await expect(cauldron.addSeries(seriesId, baseId, fyToken.address)).to.be.revertedWith('Rate oracle not found')
    })

    describe('with a rate oracle added', async () => {
      beforeEach(async () => {
        await cauldron.setLendingOracle(baseId, oracle.address)
      })

      it('does not allow not linking a series to a fyToken', async () => {
        await expect(cauldron.addSeries(seriesId, baseId, emptyAddress)).to.be.revertedWith('Series need a fyToken')
      })

      it('does not allow linking a series to the wrong base', async () => {
        await expect(cauldron.addSeries(seriesId, ilkId1, fyToken.address)).to.be.revertedWith(
          'Mismatched series and base'
        )
      })

      it('does not allow using zero as the series id', async () => {
        await expect(cauldron.addSeries('0x000000000000', baseId, fyToken.address)).to.be.revertedWith(
          'Series id is zero'
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
          await expect(cauldron.setSpotOracle(mockAssetId, ilkId1, oracle.address, ratio)).to.be.revertedWith(
            'Base not found'
          )
        })

        it('does not allow adding a spot oracle for an unknown ilk', async () => {
          await expect(cauldron.setSpotOracle(baseId, mockAssetId, oracle.address, ratio)).to.be.revertedWith(
            'Ilk not found'
          )
        })

        it('adds a spot oracle and its collateralization ratio', async () => {
          expect(await cauldron.setSpotOracle(baseId, ilkId1, oracle.address, ratio))
            .to.emit(cauldron, 'SpotOracleAdded')
            .withArgs(baseId, ilkId1, oracle.address, ratio)

          const spot = await cauldron.spotOracles(baseId, ilkId1)
          expect(spot.oracle).to.equal(oracle.address)
          expect(spot.ratio).to.equal(ratio)
        })

        describe('with an oracle for the series base and an ilk', async () => {
          beforeEach(async () => {
            await cauldron.setSpotOracle(baseId, ilkId1, oracle.address, ratio)
            await cauldron.setSpotOracle(baseId, ilkId2, oracle.address, ratio)
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
