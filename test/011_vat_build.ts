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
