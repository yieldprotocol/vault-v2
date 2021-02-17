import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import VatArtifact from '../artifacts/contracts/Vat.sol/Vat.json'
import { Vat } from '../typechain/Vat'

import { ethers, waffle } from 'hardhat'
// import { baseId } from '../src'
import { expect } from 'chai'
const { deployContract } = waffle

describe('Vat', () => {
  let ownerAcc: SignerWithAddress
  let owner: string
  let other: SignerWithAddress
  let vat: Vat

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    other = signers[1]
  })

  beforeEach(async () => {
    vat = (await deployContract(ownerAcc, VatArtifact, [])) as Vat
  })

  it('adds a base', async () => {
    const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
    const base = ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))
    expect(await vat.addBase(baseId, base)).to.emit(vat, 'BaseAdded').withArgs(baseId, base);
    expect(await vat.bases(baseId)).to.equal(base)
  })

  describe('with a base added', async () => {
    const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
    const mockBase = ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))
    const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6));
    const mockFYToken = ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))

    beforeEach(async () => {
      await vat.addBase(baseId, mockBase)
    })

    it('does not allow using the same base baseIdentifier twice', async () => {
      await expect(vat.addBase(baseId, mockBase)).to.be.revertedWith('Vat: Id already used')
    })

    /* it('adds a series', async () => {
      expect(await vat.addSeries(seriesId, baseId, mockFYToken)).to.emit(vat, 'BaseAdded').withArgs(baseId, base);
    }) */
  })

  it('builds a vault', async () => {
    const series = ethers.utils.randomBytes(6);
    const ilks = ethers.utils.randomBytes(32)
    await vat.build(series, ilks);
    const event = (await vat.queryFilter(vat.filters.VaultBuilt(null)))[0]
    const baseId = event.args.id
    const vault = await vat.vaults(baseId)
    expect(vault.owner).to.equal(owner)
    expect(vault.series).to.equal(ethers.utils.hexlify(series))
  })
})
