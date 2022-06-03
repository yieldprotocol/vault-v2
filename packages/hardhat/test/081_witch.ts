import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { RATE, ETH } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { Witch } from '../typechain/Witch'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { ChainlinkMultiOracle } from '../typechain/ChainlinkMultiOracle'
import { ISourceMock } from '../typechain/ISourceMock'
import { CompoundMultiOracle } from '../typechain/CompoundMultiOracle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'
import { getLastVaultId } from '../src/helpers'

function stringToBytes32(x: string): string {
  return ethers.utils.formatBytes32String(x)
}

const ZERO_ADDRESS = '0x' + '00'.repeat(20)

describe('Witch', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let otherAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let ladle: LadleWrapper
  let witch: Witch
  let witchFromOther: Witch
  let fyToken: FYToken
  let base: ERC20Mock
  let ilk: ERC20Mock
  let ilkJoin: Join
  let spotOracle: ChainlinkMultiOracle
  let spotSource: ISourceMock
  let rateOracle: CompoundMultiOracle
  let rateSource: ISourceMock

  const mockVaultId = ethers.utils.hexlify(ethers.utils.randomBytes(12))

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

  after(async () => {
    await loadFixture(fixture) // We advance the time to test maturity features, this rolls it back after the tests
  })

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ETH
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  let vaultId: string
  let otherVaultId: string
  let roundVaultId: string

  const posted = WAD.mul(4)
  const borrowed = WAD.mul(3)

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    witch = env.witch
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    ilkJoin = env.joins.get(ilkId) as Join
    fyToken = env.series.get(seriesId) as FYToken
    spotOracle = env.oracles.get(ilkId) as unknown as ChainlinkMultiOracle
    spotSource = (await ethers.getContractAt(
      'ISourceMock',
      (
        await spotOracle.sources(baseId, ilkId)
      )[0]
    )) as ISourceMock
    rateOracle = env.oracles.get(RATE) as unknown as CompoundMultiOracle
    rateSource = (await ethers.getContractAt('ISourceMock', await rateOracle.sources(baseId, RATE))) as ISourceMock

    witchFromOther = witch.connect(otherAcc)

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
    await ladle.pour(vaultId, owner, posted, borrowed)

    await ladle.build(seriesId, ilkId)
    otherVaultId = await getLastVaultId(cauldron)
    await ladle.pour(otherVaultId, owner, WAD, WAD)

    await ladle.build(seriesId, ilkId)
    roundVaultId = await getLastVaultId(cauldron)
    await ladle.pour(roundVaultId, owner, WAD, WAD)

    await witch.setIlk(ilkId, 3 * 60 * 60, WAD.div(2), 1000000, 0, await ilk.decimals())
  })

  it('allows to change the ladle', async () => {
    const mockAddress = owner
    expect(await witch.point(stringToBytes32('ladle'), mockAddress))
      .to.emit(witch, 'Point')
      .withArgs(stringToBytes32('ladle'), mockAddress)
    expect(await witch.ladle()).to.equal(mockAddress)
  })

  it('does not allow to set the initial proportion over 100%', async () => {
    await expect(witch.setIlk(ilkId, 1, WAD.mul(2), 1000000, 0, await ilk.decimals())).to.be.revertedWith(
      'Only at or under 100%'
    )
  })

  it('allows to set an ilk', async () => {
    expect(await witch.setIlk(ilkId, 1, 2, 3, 4, 5))
      .to.emit(witch, 'IlkSet')
      .withArgs(ilkId, 1, 2, 3, 4, 5)
    expect((await witch.ilks(ilkId)).duration).to.equal(1)
    expect((await witch.ilks(ilkId)).initialOffer).to.equal(2)
    expect((await witch.limits(ilkId)).line).to.equal(3)
    expect((await witch.limits(ilkId)).dust).to.equal(4)
    expect((await witch.limits(ilkId)).dec).to.equal(5)
  })

  it('does not allow to buy from vaults not being auctioned', async () => {
    await expect(witch.buy(vaultId, 0, 0)).to.be.revertedWith('Vault not under auction')
    await expect(witch.payAll(vaultId, 0)).to.be.revertedWith('Vault not under auction')
  })

  it('does not auction collateralized vaults', async () => {
    await expect(witch.auction(vaultId)).to.be.revertedWith('Not undercollateralized')
  })

  it('does not auction vaults if line exceeded', async () => {
    await spotSource.set(WAD.mul(2))
    await witch.setIlk(ilkId, 1, 2, 1, 0, await ilk.decimals())
    await expect(witch.auction(vaultId)).to.be.revertedWith('Collateral limit reached')
  })

  it('auctions undercollateralized vaults', async () => {
    await spotSource.set(WAD.mul(2))
    await witch.auction(vaultId)
    const event = (await witch.queryFilter(witch.filters.Auctioned(null, null)))[0]
    expect((await cauldron.vaults(vaultId)).owner).to.equal(witch.address)
    expect((await witch.auctions(vaultId)).owner).to.equal(owner)
    expect(event.args.start.toNumber()).to.be.greaterThan(0)
    expect((await witch.auctions(vaultId)).start).to.equal(event.args.start)
    expect((await witch.limits(ilkId)).sum).to.equal(posted)
  })

  describe('once a vault has been auctioned', async () => {
    beforeEach(async () => {
      await spotSource.set(WAD.mul(2))
      await witch.auction(vaultId)
    })

    it("it can't be auctioned again", async () => {
      await expect(witch.auction(vaultId)).to.be.revertedWith('Vault already under auction')
    })

    it('it can auction other vaults', async () => {
      await witch.auction(otherVaultId)
      expect((await witch.limits(ilkId)).sum).to.equal(posted.add(WAD))
    })

    it('does not auction further vaults if line exceeded', async () => {
      await witch.setIlk(ilkId, 1, 2, posted.div(WAD), 0, await ilk.decimals())
      await expect(witch.auction(otherVaultId)).to.be.revertedWith('Collateral limit reached')
    })

    it('does not buy if minimum collateral not reached', async () => {
      await expect(witch.buy(vaultId, WAD, WAD)).to.be.revertedWith('Not enough bought')
    })

    it('it can buy no collateral (coverage)', async () => {
      expect(await witch.buy(vaultId, 0, 0))
        .to.emit(witch, 'Bought')
        .withArgs(vaultId, owner, 0, 0)
    })

    describe.skip('TODO: Being rewritten as part of Witch v2', async () => {
      it('allows to buy 1/2 of the collateral for the whole debt at the beginning', async () => {
        const baseBalanceBefore = await base.balanceOf(owner)
        const ilkBalanceBefore = await ilk.balanceOf(owner)
        await expect(witch.buy(vaultId, borrowed, 0))
          .to.emit(witch, 'Bought')
          .withArgs(vaultId, owner, (await ilk.balanceOf(owner)).sub(ilkBalanceBefore), borrowed)
          .to.emit(cauldron, 'VaultGiven')
          .withArgs(vaultId, owner)

        const ink = posted.sub((await cauldron.balances(vaultId)).ink)
        expect(ink.div(10 ** 15)).to.equal(posted.div(10 ** 15).div(2)) // Nice hack to compare up to some precision
        expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(borrowed))
        expect(await ilk.balanceOf(owner)).to.equal(ilkBalanceBefore.add(ink))
        expect((await cauldron.vaults(vaultId)).owner).to.equal(owner) // The vault was returned once all the debt was paid off
      })
    })

    it('does not buy if leaving dust', async () => {
      await witch.setIlk(ilkId, 3 * 60 * 60, WAD.div(2), 1000000, posted.div(WAD), await ilk.decimals())
      await expect(witch.buy(vaultId, WAD, 0)).to.be.revertedWith('Leaves dust')
    })

    describe('once the auction time has passed', async () => {
      beforeEach(async () => {
        const { timestamp } = await ethers.provider.getBlock('latest')
        await ethers.provider.send('evm_mine', [timestamp + (await witch.ilks(ilkId)).duration])
      })

      it('allows to buy all of the collateral for the whole debt at the end', async () => {
        const baseBalanceBefore = await base.balanceOf(owner)
        const ilkBalanceBefore = await ilk.balanceOf(owner)
        await expect(witch.payAll(vaultId, 0)).to.emit(witch, 'Bought').withArgs(vaultId, owner, posted, borrowed)

        const ink = posted.sub((await cauldron.balances(vaultId)).ink)
        expect(ink).to.equal(posted)
        expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(borrowed))
        expect(await ilk.balanceOf(owner)).to.equal(ilkBalanceBefore.add(ink))
        expect((await witch.auctions(vaultId)).owner).to.equal(ZERO_ADDRESS)
      })

      describe('after maturity, with a rate increase', async () => {
        beforeEach(async () => {
          await ethers.provider.send('evm_mine', [(await fyToken.maturity()).toNumber()])
          await cauldron.mature(seriesId)
          const rate = await cauldron.ratesAtMaturity(seriesId)
          await rateSource.set(rate.mul(110).div(100))
        })

        /*
        TODO: To be rewritten in foundry
        it('debt to repay grows with rate after maturity', async () => {
          await cauldron.setDebtLimits(baseId, ilkId, 1000000, 0, 18) // Disable the dust level, not relevant

          const baseBalanceBefore = await base.balanceOf(owner)
          const ilkBalanceBefore = await ilk.balanceOf(owner)
          await expect(witch.buy(vaultId, borrowed, 0))
            .to.emit(witch, 'Bought')
            .withArgs(
              vaultId,
              owner,
              posted.sub((await cauldron.balances(vaultId)).ink),
              borrowed.sub((await cauldron.balances(vaultId)).art)
            )

          const art = borrowed.sub((await cauldron.balances(vaultId)).art)
          const ink = posted.sub((await cauldron.balances(vaultId)).ink)
          expect(art).to.equal(borrowed.mul(100).div(110).add(1)) // The rate increased by a 10%, so by paying WAD base we only repay 100/110 of the debt in fyToken terms
          expect(ink).to.equal(posted.mul(100).div(110).add(2)) // We only pay 100/110 of the debt, so we get 100/110 of the collateral
          expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(borrowed))
          expect(await ilk.balanceOf(owner)).to.equal(ilkBalanceBefore.add(ink))
        })
        */

        it('allows to pay all of the debt', async () => {
          const baseBalanceBefore = await base.balanceOf(owner)
          const ilkBalanceBefore = await ilk.balanceOf(owner)
          await expect(witch.payAll(vaultId, 0)).to.emit(witch, 'Bought').withArgs(vaultId, owner, posted, borrowed)

          expect((await cauldron.balances(vaultId)).art).to.equal(0)
          expect((await cauldron.balances(vaultId)).ink).to.equal(0)
          expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(borrowed.mul(110).div(100)))
          expect(await ilk.balanceOf(owner)).to.equal(ilkBalanceBefore.add(posted))
          expect((await witch.auctions(vaultId)).owner).to.equal(ZERO_ADDRESS)
        })
      })
    })
  })
})
