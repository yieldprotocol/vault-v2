import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { expect } from 'chai'
import { ethers, waffle } from 'hardhat'
import { ETH } from '../src/constants'
import { Cauldron, ContangoLadle } from '../typechain'
import { YieldEnvironment } from './shared/contango_fixtures'

const { loadFixture } = waffle

describe('ContangoLadle', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let owner: string
  let cauldron: Cauldron
  let ladle: ContangoLadle

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ETH
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
  })

  it("doesn't allow the regular build method", async () => {
    await expect(ladle.build(seriesId, ilkId, 0)).to.be.revertedWith('Use deterministicBuild')
  })

  it('builds a vault with a deterministic id', async () => {
    const vaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12))
    await expect(ladle.deterministicBuild(vaultId, seriesId, ilkId)).to.emit(cauldron, 'VaultBuilt')

    const logs = await cauldron.queryFilter(cauldron.filters.VaultBuilt(null, null, null, null))
    const event = logs[logs.length - 1]
    expect(event.args.vaultId).to.equal(vaultId)
    expect(event.args.owner).to.equal(owner)
    expect(event.args.seriesId).to.equal(seriesId)
    expect(event.args.ilkId).to.equal(ilkId)

    const vault = await cauldron.vaults(vaultId)
    expect(vault.owner).to.equal(owner)
    expect(vault.seriesId).to.equal(seriesId)
    expect(vault.ilkId).to.equal(ilkId)
  })
})
