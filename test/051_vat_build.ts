import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import VatArtifact from '../artifacts/contracts/Vat.sol/Vat.json'
import FYTokenArtifact from '../artifacts/contracts/FYToken.sol/FYToken.json'
import ERC20MockArtifact from '../artifacts/contracts/mocks/ERC20Mock.sol/ERC20Mock.json'

import { Vat } from '../typechain/Vat'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'

import { ethers, waffle } from 'hardhat'
// import { id } from '../src'
import { expect } from 'chai'
const { deployContract } = waffle

describe('Vat', () => {
  let ownerAcc: SignerWithAddress
  let owner: string
  let otherAcc: SignerWithAddress
  let other: string
  let vat: Vat
  let vatFromOther: Vat
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock

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

    vatFromOther = vat.connect(otherAcc)
  })

  it('adds an asset', async () => {
    expect(await vat.addAsset(ilkId, ilk.address)).to.emit(vat, 'AssetAdded').withArgs(ilkId, ilk.address)
    expect(await vat.assets(ilkId)).to.equal(ilk.address)
  })

  it('does not allow adding a series before adding its base', async () => {
    await expect(vat.addSeries(seriesId, baseId, fyToken.address)).to.be.revertedWith('Vat: Asset not found')
  })

  describe('with a base and an ilk added', async () => {
    beforeEach(async () => {
      await vat.addAsset(baseId, base.address)
      await vat.addAsset(ilkId, ilk.address)
    })

    it('does not allow using the same asset identifier twice', async () => {
      await expect(vat.addAsset(baseId, base.address)).to.be.revertedWith('Vat: Id already used')
    })

    it('does not allow not linking a series to a fyToken', async () => {
      await expect(vat.addSeries(seriesId, baseId, emptyAddress)).to.be.revertedWith('Vat: Series need a fyToken')
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
        await expect(vat.addSeries(seriesId, baseId, fyToken.address)).to.be.revertedWith('Vat: Id already used')
      })

      it('does not allow adding an asset as an ilk to a series that doesn\'t exist', async () => {
        await expect(vat.addIlk(mockSeriesId, ilkId)).to.be.revertedWith('Vat: Series not found')
      })

      it('does not allow adding an asset that doesn\'t exist as an ilk', async () => {
        await expect(vat.addIlk(seriesId, mockAssetId)).to.be.revertedWith('Vat: Asset not found')
      })
  
      it('does not build a vault with an ilk that is not approved for a series', async () => {
        await expect(vat.build(seriesId, ilkId)).to.be.revertedWith('Vat: Ilk not added')
      })

      it('adds an asset as an ilk to a series', async () => {
        expect(await vat.addIlk(seriesId, ilkId)).to.emit(vat, 'IlkAdded').withArgs(seriesId, ilkId)
  
        expect(await vat.ilks(seriesId, ilkId)).to.be.true
      })

      describe('with an asset added as an ilk to a series', async () => {
        beforeEach(async () => {
          await vat.addIlk(seriesId, ilkId)
        })

        it('does not build a vault with an unknown series', async () => { // TODO: Error message misleading, replace in contract for something generic
          await expect(vat.build(mockAssetId, ilkId)).to.be.revertedWith('Vat: Ilk not added')
        })
    
        it('does not build a vault with an unknown ilk', async () => { // TODO: Might be removed, redundant with approved ilk check
          await expect(vat.build(seriesId, mockAssetId)).to.be.revertedWith('Vat: Ilk not added')
        })

        it('builds a vault', async () => {
          // expect(await vat.build(seriesId, mockIlks)).to.emit(vat, 'VaultBuilt').withArgs(null, seriesId, mockIlks);
          await vat.build(seriesId, ilkId)
          const event = (await vat.queryFilter(vat.filters.VaultBuilt(null, null, null, null)))[0]
          const vaultId = event.args.vaultId
          const vault = await vat.vaults(vaultId)
          expect(vault.owner).to.equal(owner)
          expect(vault.seriesId).to.equal(seriesId)
          expect(vault.ilkId).to.equal(ilkId)

          // Remove these two when `expect...to.emit` works
          expect(event.args.owner).to.equal(owner)
          expect(event.args.seriesId).to.equal(seriesId)
          expect(event.args.ilkId).to.equal(ilkId)
        })

        describe('with a vault built', async () => {
          let vaultId: string

          beforeEach(async () => {
            await vat.build(seriesId, ilkId)
            const event = (await vat.queryFilter(vat.filters.VaultBuilt(null, null, null, null)))[0]
            vaultId = event.args.vaultId
          })
    
          it('does not allow destroying vaults if not the vault owner', async () => {
            await expect(vatFromOther.destroy(vaultId)).to.be.revertedWith('Vat: Only vault owner')
          })
    
          it('destroys a vault', async () => {
            expect(await vat.destroy(vaultId)).to.emit(vat, 'VaultDestroyed').withArgs(vaultId)
            const vault = await vat.vaults(vaultId)
            expect(vault.owner).to.equal(emptyAddress)
            expect(vault.seriesId).to.equal(emptyAssetId)
            expect(vault.ilkId).to.equal(emptyAssetId)
          })

          it('does not allow giving vaults if not the vault owner', async () => {
            await expect(vatFromOther.give(vaultId, other)).to.be.revertedWith('Vat: Only vault owner')
          })
    
          it('gives a vault', async () => {
            expect(await vat.give(vaultId, other)).to.emit(vat, 'VaultTransfer').withArgs(vaultId, other)
            const vault = await vat.vaults(vaultId)
            expect(vault.owner).to.equal(other)
            expect(vault.seriesId).to.equal(seriesId)
            expect(vault.ilkId).to.equal(ilkId)
          })
        })
      })
    })
  })
})
