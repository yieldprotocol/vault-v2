import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { Vat } from '../typechain/Vat'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'

import { YieldEnvironment } from './shared/fixtures'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

describe('Vat - Vaults', () => {
  let ownerAcc: SignerWithAddress
  let owner: string
  let otherAcc: SignerWithAddress
  let other: string
  let env: YieldEnvironment
  let vat: Vat
  let vatFromOther: Vat
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock

  const baseId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6));

  const mockAssetId =  ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const emptyAssetId = '0x000000000000'
  const mockAddress =  ethers.utils.getAddress(ethers.utils.hexlify(ethers.utils.randomBytes(20)))
  const emptyAddress =  ethers.utils.getAddress('0x0000000000000000000000000000000000000000')

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, otherAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  beforeEach(async () => {
    env = await loadFixture(fixture);
    vat = env.vat
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken

    vatFromOther = vat.connect(otherAcc)

    await vat.setMaxDebt(baseId, ilkId, 2)
  })

  it('does not build a vault with an unknown series', async () => { // TODO: Error message misleading, replace in contract for something generic
    await expect(vat.build(mockAssetId, ilkId)).to.be.revertedWith('Vat: Ilk not added')
  })

  it('does not build a vault with an unknown ilk', async () => { // TODO: Might be removed, redundant with approved ilk check
    await expect(vat.build(seriesId, mockAssetId)).to.be.revertedWith('Vat: Ilk not added')
  })

  it('does not build a vault with an ilk that is not approved for a series', async () => {
    await vat.addAsset(mockAssetId, mockAddress)
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
