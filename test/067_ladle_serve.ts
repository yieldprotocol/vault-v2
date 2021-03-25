import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { Cauldron } from '../typechain/Cauldron'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment, WAD } from './shared/fixtures'

describe('Ladle - serve', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock
  let ladle: Ladle

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
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

  let vaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    fyToken = env.series.get(seriesId) as FYToken

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
  })

  /*
  it('borrows and sells for base', async () => {
    const baseBalanceBefore = await base.balanceOf(owner)
    const ilkBalanceBefore = await ilk.balanceOf(owner)
    expect(await ladle.serve(vaultId, owner, WAD, WAD, 0))
      .to.emit(cauldron, 'VaultPoured')
      .withArgs(vaultId, seriesId, ilkId, WAD, WAD)
    expect((await cauldron.balances(vaultId)).ink).to.equal(WAD)
    expect((await cauldron.balances(vaultId)).art).to.equal(WAD)
    expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.add(WAD.mul(100).div(105)))
    expect(await ilk.balanceOf(owner)).to.equal(ilkBalanceBefore.sub(WAD))
  })

  it('does not `serve` if slippage exceeded', async () => {
    await expect(ladle.serve(vaultId, owner, WAD, WAD, WAD.mul(2))).to.be.revertedWith(
      'Pool: Not enough baseToken obtained'
    )
  })
  */
})
