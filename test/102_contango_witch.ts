import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { constants } from '@yield-protocol/utils-v2'
import { expect } from 'chai'
import { parseUnits } from 'ethers/lib/utils'
import { ethers, waffle } from 'hardhat'
import { ETH } from '../src/constants'
import {
  ChainlinkMultiOracle,
  ContangoCauldron,
  ContangoLadle,
  ContangoWitch,
  ERC20Mock,
  ISourceMock,
} from '../typechain'
import { YieldEnvironment } from './shared/contango_fixtures'

const { WAD } = constants

const { loadFixture } = waffle

function stringToBytes32(x: string): string {
  return ethers.utils.formatBytes32String(x)
}

const ZERO_ADDRESS = '0x' + '00'.repeat(20)

describe('ContangoWitch', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let owner: string
  let cauldron: ContangoCauldron
  let ladle: ContangoLadle
  let witch: ContangoWitch
  let ilk: ERC20Mock
  let spotOracle: ChainlinkMultiOracle
  let spotSource: ISourceMock

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  after(async () => {
    await loadFixture(fixture) // We advance the time to test maturity features, this rolls it back after the tests
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ETH
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  let vaultId: string
  let otherVaultId: string

  const posted = WAD.mul(4)
  const borrowed = WAD.mul(3)

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    witch = env.witch
    ilk = env.assets.get(ilkId) as ERC20Mock

    spotOracle = env.oracles.get(ilkId) as unknown as ChainlinkMultiOracle
    spotSource = (await ethers.getContractAt(
      'ISourceMock',
      (
        await spotOracle.sources(baseId, ilkId)
      )[0]
    )) as ISourceMock

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
    await ladle.pour(vaultId, owner, posted, borrowed)

    otherVaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12))
    await ladle.deterministicBuild(otherVaultId, seriesId, ilkId)
    await ladle.pour(otherVaultId, owner, WAD, WAD)

    await witch.setIlk(ilkId, 3 * 60 * 60, WAD.div(2), 1000000, 0, await ilk.decimals())
  })

  it('does not auction collateralized vaults', async () => {
    await expect(witch.auction(vaultId)).to.be.revertedWith('Not undercollateralized')
  })

  it('does not auction undercollateralized vaults if the overall system is healthy', async () => {
    await cauldron.pour(otherVaultId, parseUnits('10'), parseUnits('20000', 6))

    await spotSource.set(WAD.mul(2))
    await expect(witch.auction(vaultId)).to.be.revertedWith('Not undercollateralized')
  })

  it('auctions undercollateralized vaults if the overall system is unhealthy', async () => {
    await spotSource.set(WAD.mul(2))
    await witch.auction(vaultId)
    const event = (await witch.queryFilter(witch.filters.Auctioned(null, null)))[0]
    expect((await cauldron.vaults(vaultId)).owner).to.equal(witch.address)
    expect((await witch.auctions(vaultId)).owner).to.equal(owner)
    expect(event.args.start.toNumber()).to.be.greaterThan(0)
    expect((await witch.auctions(vaultId)).start).to.equal(event.args.start)
    expect((await witch.limits(ilkId)).sum).to.equal(posted)
  })
})
