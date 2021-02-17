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
  let other: SignerWithAddress
  let vat: Vat
  let fyToken: FYToken
  let base: ERC20Mock

  const mockAddress =  ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    other = signers[1]
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
  const maturity = 1640995199;

  beforeEach(async () => {
    vat = (await deployContract(ownerAcc, VatArtifact, [])) as Vat
    base = (await deployContract(ownerAcc, ERC20MockArtifact, [baseId, "Mock Base"])) as ERC20Mock
    fyToken = (await deployContract(ownerAcc, FYTokenArtifact, [base.address, mockAddress, maturity, seriesId, "Mock FYToken"])) as FYToken
  })

  it('adds a base', async () => {
    expect(await vat.addBase(baseId, base.address)).to.emit(vat, 'BaseAdded').withArgs(baseId, base.address)
    expect(await vat.bases(baseId)).to.equal(base.address)
  })

  describe('with a base added', async () => {
    beforeEach(async () => {
      await vat.addBase(baseId, base.address)
    })

    it('does not allow using the same base baseIdentifier twice', async () => {
      await expect(vat.addBase(baseId, base.address)).to.be.revertedWith('Vat: Id already used')
    })

    it('adds a series', async () => {
      expect(await vat.addSeries(seriesId, baseId, fyToken.address)).to.emit(vat, 'SeriesAdded').withArgs(seriesId, baseId, fyToken.address)

      const series = await vat.series(seriesId)
      expect(series.fyToken).to.equal(fyToken.address)
      expect(series.baseId).to.equal(baseId)
      expect(series.maturity).to.equal(maturity)
    })
  })

  it('builds a vault', async () => {
    const ilks = ethers.utils.hexlify(ethers.utils.randomBytes(32))
    // expect(await vat.build(seriesId, ilks)).to.emit(vat, 'VaultBuilt').withArgs(null, seriesId, ilks);
    await vat.build(seriesId, ilks)
    const event = (await vat.queryFilter(vat.filters.VaultBuilt(null, null, null)))[0]
    const vaultId = event.args.vaultId
    const vault = await vat.vaults(vaultId)
    expect(vault.owner).to.equal(owner)
    expect(vault.seriesId).to.equal(seriesId)

    // Remove these two when `expect...to.emit` works
    expect(event.args.seriesId).to.equal(seriesId)
    expect(event.args.ilks).to.equal(ilks)
  })
})
