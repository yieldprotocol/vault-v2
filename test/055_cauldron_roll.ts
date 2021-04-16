import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { WAD } from './shared/constants'

import { Cauldron } from '../typechain/Cauldron'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'

describe('Cauldron - roll', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let cauldronFromOther: Cauldron
  let fyToken: FYToken
  let otherFYToken: FYToken
  let base: ERC20Mock
  let ladle: Ladle
  let ladleFromOther: Ladle

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId, otherSeriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()

    otherAcc = signers[1]
    other = await otherAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const vaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12))
  const otherSeriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockSeriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const mockVaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12))

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken
    otherFYToken = env.series.get(otherSeriesId) as FYToken

    cauldronFromOther = cauldron.connect(otherAcc)

    // ==== Set testing environment ====
    await cauldron.build(owner, vaultId, seriesId, ilkId)
    await cauldron.pour(vaultId, WAD, WAD)
  })

  it('does not allow rolling unknown vaults', async () => {
    await expect(cauldron.roll(mockVaultId, otherSeriesId, 0)).to.be.revertedWith('Vault not found')
  })

  it('does not allow rolling and becoming undercollateralized', async () => {
    await expect(cauldron.roll(vaultId, otherSeriesId, WAD.mul(3))).to.be.revertedWith('Undercollateralized')
  })

  it('rolls a vault', async () => {
    expect(await cauldron.roll(vaultId, otherSeriesId, WAD.div(2)))
      .to.emit(cauldron, 'VaultRolled')
      .withArgs(vaultId, otherSeriesId, WAD.div(2))
    expect((await cauldron.vaults(vaultId)).seriesId).to.equal(otherSeriesId)
    expect((await cauldron.balances(vaultId)).ink).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).art).to.equal(WAD.div(2))
  })
})
