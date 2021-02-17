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

  const mockAssetId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const emptyAssetId = '0x000000000000'
  const mockVaultId =  ethers.utils.hexlify(ethers.utils.randomBytes(12))
  const mockAddress =  ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))
  const mockIlks = ethers.utils.hexlify(ethers.utils.randomBytes(32))
  const emptyAddress =  ethers.utils.getAddress('0x0000000000000000000000000000000000000000')

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const maturity = 1640995199;

  beforeEach(async () => {
    vat = (await deployContract(ownerAcc, VatArtifact, [])) as Vat
    base = (await deployContract(ownerAcc, ERC20MockArtifact, [baseId, "Mock Base"])) as ERC20Mock
    fyToken = (await deployContract(ownerAcc, FYTokenArtifact, [base.address, mockAddress, maturity, seriesId, "Mock FYToken"])) as FYToken

    vatFromOther = vat.connect(otherAcc)
  })

  it('adds a base', async () => {
    expect(await vat.addBase(baseId, base.address)).to.emit(vat, 'BaseAdded').withArgs(baseId, base.address)
    expect(await vat.bases(baseId)).to.equal(base.address)
  })

  it('does not allow adding a series before adding its base', async () => {
    await expect(vat.addSeries(seriesId, baseId, fyToken.address)).to.be.revertedWith('Vat: Base not found')
  })

  describe('with a base added', async () => {
    beforeEach(async () => {
      await vat.addBase(baseId, base.address)
    })

    it('does not allow using the same base identifier twice', async () => {
      await expect(vat.addBase(baseId, base.address)).to.be.revertedWith('Vat: Id already used')
    })

    it('does not allow not linking to a fyToken', async () => {
      await expect(vat.addSeries(seriesId, baseId, emptyAddress)).to.be.revertedWith('Vat: Series need a fyToken')
    })

    it('adds a series', async () => {
      expect(await vat.addSeries(seriesId, baseId, fyToken.address)).to.emit(vat, 'SeriesAdded').withArgs(seriesId, baseId, fyToken.address)

      const series = await vat.series(seriesId)
      expect(series.fyToken).to.equal(fyToken.address)
      expect(series.baseId).to.equal(baseId)
      expect(series.maturity).to.equal(maturity)
    })

    it('does not build a vault not linked to a series', async () => {
      await expect(vat.build(mockAssetId, mockIlks)).to.be.revertedWith('Vat: Series not found')
    })

    describe('with a series added', async () => {
      beforeEach(async () => {
        await vat.addSeries(seriesId, baseId, fyToken.address)
      })

      it('does not allow using the same series identifier twice', async () => {
        await expect(vat.addSeries(seriesId, baseId, fyToken.address)).to.be.revertedWith('Vat: Id already used')
      })

      it('builds a vault', async () => {
        // expect(await vat.build(seriesId, mockIlks)).to.emit(vat, 'VaultBuilt').withArgs(null, seriesId, mockIlks);
        await vat.build(seriesId, mockIlks)
        const event = (await vat.queryFilter(vat.filters.VaultBuilt(null, null, null, null)))[0]
        const vaultId = event.args.vaultId
        const vault = await vat.vaults(vaultId)
        expect(vault.owner).to.equal(owner)
        expect(vault.seriesId).to.equal(seriesId)

        // Remove these two when `expect...to.emit` works
        expect(event.args.owner).to.equal(owner)
        expect(event.args.seriesId).to.equal(seriesId)
        expect(event.args.ilks).to.equal(mockIlks)
      })

      describe('with a vault built', async () => {
        let vaultId: string

        beforeEach(async () => {
          await vat.build(seriesId, mockIlks)
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
        })

        it('does not allow giving vaults if not the vault owner', async () => {
          await expect(vatFromOther.give(vaultId, other)).to.be.revertedWith('Vat: Only vault owner')
        })
  
        it('gives a vault', async () => {
          expect(await vat.give(vaultId, other)).to.emit(vat, 'VaultTransfer').withArgs(vaultId, other)
          const vault = await vat.vaults(vaultId)
          expect(vault.owner).to.equal(other)
          expect(vault.seriesId).to.equal(seriesId)
        })
      })
    })
  })
})
