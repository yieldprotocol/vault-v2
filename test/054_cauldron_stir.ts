import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { ETH } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'

describe('Cauldron - stir', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let cauldronFromOther: Cauldron
  let fyToken: FYToken
  let base: ERC20Mock

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId, otherIlkId], [seriesId, otherSeriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ETH
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const vaultToId = ethers.utils.hexlify(ethers.utils.randomBytes(12))
  const otherIlkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const otherSeriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockVaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12))

  let vaultFromId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    cauldronFromOther = cauldron.connect(otherAcc)
    base = env.assets.get(baseId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken

    vaultFromId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string

    // ==== Set testing environment ====
    await cauldron.build(owner, vaultToId, seriesId, ilkId)
  })

  it('does not allow moving collateral or debt from and to the same vault', async () => {
    await expect(cauldron.stir(vaultFromId, vaultFromId, WAD, WAD)).to.be.revertedWith('Identical vaults')
  })

  it('does not allow moving collateral or debt to an uninitialized vault', async () => {
    await expect(cauldron.stir(mockVaultId, vaultToId, WAD, 0)).to.be.revertedWith('Vault not found')
    await expect(cauldron.stir(vaultFromId, mockVaultId, WAD, 0)).to.be.revertedWith('Vault not found')
  })

  it('does not allow moving collateral to vault of a different ilk', async () => {
    await cauldron.tweak(vaultToId, seriesId, otherIlkId)
    await expect(cauldron.stir(vaultFromId, vaultToId, WAD, 0)).to.be.revertedWith('Different collateral')
  })

  it('does not allow moving debt to vault of a different series', async () => {
    await cauldron.tweak(vaultToId, otherSeriesId, ilkId)
    await expect(cauldron.stir(vaultFromId, vaultToId, 0, WAD)).to.be.revertedWith('Different series')
  })

  it('does not allow moving collateral and becoming undercollateralized at origin', async () => {
    await cauldron.pour(vaultFromId, WAD, WAD)
    await expect(cauldron.stir(vaultFromId, vaultToId, WAD, 0)).to.be.revertedWith('Undercollateralized at origin')
  })

  it('does not allow moving debt and becoming undercollateralized at destination', async () => {
    await cauldron.pour(vaultFromId, WAD, WAD)
    await expect(cauldron.stir(vaultFromId, vaultToId, 0, WAD)).to.be.revertedWith('Undercollateralized at destination')
  })

  it('moves collateral', async () => {
    await cauldron.pour(vaultFromId, WAD, 0)
    expect(await cauldron.stir(vaultFromId, vaultToId, WAD, 0))
      .to.emit(cauldron, 'VaultStirred')
      .withArgs(vaultFromId, vaultToId, WAD, 0)
    expect((await cauldron.balances(vaultFromId)).ink).to.equal(0)
    expect((await cauldron.balances(vaultToId)).ink).to.equal(WAD)
  })

  it('moves debt', async () => {
    await cauldron.pour(vaultFromId, WAD, WAD)
    await cauldron.pour(vaultToId, WAD, 0)
    expect(await cauldron.stir(vaultFromId, vaultToId, 0, WAD))
      .to.emit(cauldron, 'VaultStirred')
      .withArgs(vaultFromId, vaultToId, 0, WAD)
    expect((await cauldron.balances(vaultFromId)).art).to.equal(0)
    expect((await cauldron.balances(vaultToId)).art).to.equal(WAD)
  })
})
