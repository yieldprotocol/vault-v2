import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import VatArtifact from '../artifacts/contracts/Vat.sol/Vat.json'
import FYTokenArtifact from '../artifacts/contracts/FYToken.sol/FYToken.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'
import OracleMockArtifact from '../artifacts/contracts/mocks/OracleMock.sol/OracleMock.json'

import { Vat } from '../typechain/Vat'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { OracleMock } from '../typechain/OracleMock'

import { ethers, waffle } from 'hardhat'
// import { id } from '../src'
import { expect } from 'chai'
const { deployContract } = waffle

describe('Vat - Admin', () => {
  let ownerAcc: SignerWithAddress
  let owner: string
  let otherAcc: SignerWithAddress
  let other: string
  let vat: Vat
  let vatFromOther: Vat
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock
  let oracle: OracleMock

  const mockAssetId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockSeriesId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const emptyAssetId = '0x000000000000'
  const mockVaultId =  ethers.utils.hexlify(ethers.utils.randomBytes(12))
  const mockAddress =  ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))
  const emptyAddress =  ethers.utils.getAddress('0x0000000000000000000000000000000000000000')

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const maturity = 1640995199;

  beforeEach(async () => {
    vat = (await deployContract(ownerAcc, VatArtifact, [])) as Vat
    base = (await deployContract(ownerAcc, ERC20MockArtifact, [baseId, "Mock Base"])) as ERC20Mock
    ilk = (await deployContract(ownerAcc, ERC20MockArtifact, [ilkId, "Mock Ilk"])) as ERC20Mock
    fyToken = (await deployContract(ownerAcc, FYTokenArtifact, [base.address, mockAddress, maturity, seriesId, "Mock FYToken"])) as FYToken
    oracle = (await deployContract(ownerAcc, OracleMockArtifact, [])) as OracleMock

    vatFromOther = vat.connect(otherAcc)
  })

  it('adds an asset', async () => {
    expect(await vat.addAsset(ilkId, ilk.address)).to.emit(vat, 'AssetAdded').withArgs(ilkId, ilk.address)
    expect(await vat.assets(ilkId)).to.equal(ilk.address)
  })

  it('does not allow adding a series before adding its base', async () => {
    await expect(vat.addSeries(seriesId, baseId, fyToken.address)).to.be.revertedWith('Asset not found')
  })

  describe('with a base and an ilk added', async () => {
    beforeEach(async () => {
      await vat.addAsset(baseId, base.address)
      await vat.addAsset(ilkId, ilk.address)
    })

    it('does not allow using the same asset identifier twice', async () => {
      await expect(vat.addAsset(baseId, base.address)).to.be.revertedWith('Id already used')
    })

    it('does not allow setting a debt limit for an unknown base', async () => {
      await expect(vat.setMaxDebt(mockAssetId, ilkId, 2)).to.be.revertedWith('Asset not found')
    })
  
    it('does not allow setting a debt limit for an unknown ilk', async () => {
      await expect(vat.setMaxDebt(baseId, mockAssetId, 2)).to.be.revertedWith('Asset not found')
    })

    it('sets a debt limit', async () => {
      expect(await vat.setMaxDebt(baseId, ilkId, 2)).to.emit(vat, 'MaxDebtSet').withArgs(baseId, ilkId, 2)

      const debt = await vat.debt(baseId, ilkId)
      expect(debt.max).to.equal(2)
    })

    it('does not allow adding a spot oracle for an unknown base', async () => {
      await expect(vat.addSpotOracle(mockAssetId, ilkId, oracle.address)).to.be.revertedWith('Asset not found')
    })

    it('does not allow adding a spot oracle for an unknown ilk', async () => {
      await expect(vat.addSpotOracle(baseId, mockAssetId, oracle.address)).to.be.revertedWith('Asset not found')
    })

    it('adds a spot oracle', async () => {
      expect(await vat.addSpotOracle(baseId, ilkId, oracle.address)).to.emit(vat, 'SpotOracleAdded').withArgs(baseId, ilkId, oracle.address)

      expect(await vat.spotOracles(baseId, ilkId)).to.equal(oracle.address)
    })

    it('does not allow not linking a series to a fyToken', async () => {
      await expect(vat.addSeries(seriesId, baseId, emptyAddress)).to.be.revertedWith('Series need a fyToken')
    })

    it('adds a series', async () => {
      expect(await vat.addSeries(seriesId, baseId, fyToken.address)).to.emit(vat, 'SeriesAdded').withArgs(seriesId, baseId, fyToken.address)

      const series = await vat.series(seriesId)
      expect(series.fyToken).to.equal(fyToken.address)
      expect(series.baseId).to.equal(baseId)
      expect(series.maturity).to.equal(maturity)
    })

    describe('with a series added', async () => {
      beforeEach(async () => {
        await vat.addSeries(seriesId, baseId, fyToken.address)
      })

      it('does not allow using the same series identifier twice', async () => {
        await expect(vat.addSeries(seriesId, baseId, fyToken.address)).to.be.revertedWith('Id already used')
      })

      describe('with an oracle for the series base and an ilk', async () => {
        beforeEach(async () => {
          await vat.addSpotOracle(baseId, ilkId, oracle.address)
        })

        it('does not allow adding an asset as an ilk to a series that doesn\'t exist', async () => {
          await expect(vat.addIlk(mockSeriesId, ilkId)).to.be.revertedWith('Series not found')
        })

        it('does not allow adding an asset as an ilk without an oracle for a series base', async () => {
          await expect(vat.addIlk(seriesId, mockAssetId)).to.be.revertedWith('Oracle not found')
        })

        it('adds an asset as an ilk to a series', async () => {
          expect(await vat.addIlk(seriesId, ilkId)).to.emit(vat, 'IlkAdded').withArgs(seriesId, ilkId)
    
          expect(await vat.ilks(seriesId, ilkId)).to.be.true
        })
      })
    })
  })
})
