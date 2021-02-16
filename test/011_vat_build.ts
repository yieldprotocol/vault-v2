import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import VatArtifact from '../artifacts/contracts/Vat.sol/Vat.json'
import { Vat } from '../typechain/Vat'

import { ethers, waffle } from 'hardhat'
// import { id } from '../src'
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
    const id = ethers.utils.hexlify(ethers.utils.randomBytes(6));
    const base = ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))
    expect(await vat.addBase(id, base)).to.emit(vat, 'BaseAdded').withArgs(id, base);
    expect(await vat.bases(id)).to.equal(base)
  })

  describe('with a base added', async () => {
    const id = ethers.utils.hexlify(ethers.utils.randomBytes(6));
    const base = ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))

    beforeEach(async () => {
      await vat.addBase(id, base)
    })

    it('does not allow using the same base identifier twice', async () => {
      await expect(vat.addBase(id, base)).to.be.revertedWith('Vat: Base already present')
    })
  })

  it('builds a vault', async () => {
    const series = ethers.utils.randomBytes(6);
    const ilks = ethers.utils.randomBytes(32)
    await vat.build(series, ilks);
    const event = (await vat.queryFilter(vat.filters.VaultBuilt(null)))[0]
    const id = event.args.id
    const vault = await vat.vaults(id)
    expect(vault.owner).to.equal(owner)
    expect(vault.series).to.equal(ethers.utils.hexlify(series))
  })
})
