import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { Cauldron } from '../typechain/Cauldron'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment, WAD } from './shared/fixtures'

describe('Ladle - roll', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let fyToken: FYToken
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

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken

    ladleFromOther = ladle.connect(otherAcc)

    // ==== Set testing environment ====
    await cauldron.build(owner, vaultId, seriesId, ilkId)
    await ladle.pour(vaultId, owner, WAD, WAD)
  })

  it('does not allow rolling vaults other than to the vault owner', async () => {
    await expect(ladleFromOther.roll(vaultId, seriesId, WAD)).to.be.revertedWith('Only vault owner')
  })

  it('rolls a vault', async () => {
    expect(await ladle.roll(vaultId, otherSeriesId, WAD.div(-2)))
      .to.emit(cauldron, 'VaultRolled')
      .withArgs(vaultId, otherSeriesId, WAD.div(2))
    expect((await cauldron.vaults(vaultId)).seriesId).to.equal(otherSeriesId)
    expect((await cauldron.balances(vaultId)).ink).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).art).to.equal(WAD.div(2))
  })
})
