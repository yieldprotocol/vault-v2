import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { RATE } from '../src/constants'

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

function bytes6ToBytes32(x: string): string {
  return x + '00'.repeat(26)
}

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

  const baseId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  let vaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    witch = env.witch
    base = env.assets.get(baseId) as ERC20Mock
    ilk = env.assets.get(ilkId) as ERC20Mock
    ilkJoin = env.joins.get(ilkId) as Join
    fyToken = env.series.get(seriesId) as FYToken
    spotOracle = (env.oracles.get(ilkId) as unknown) as ChainlinkMultiOracle
    spotSource = (await ethers.getContractAt(
      'ISourceMock',
      (await spotOracle.sources(baseId, ilkId))[0]
    )) as ISourceMock
    rateOracle = (env.oracles.get(RATE) as unknown) as CompoundMultiOracle
    rateSource = (await ethers.getContractAt('ISourceMock', await rateOracle.sources(baseId, RATE))) as ISourceMock

    witchFromOther = witch.connect(otherAcc)

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
    await ladle.pour(vaultId, owner, WAD, WAD)
  })

  it('does not allow to set the initial proportion over 100%', async () => {
    await expect(witch.setInitialOffer(WAD.mul(2))).to.be.revertedWith('Only at or under 100%')
  })

  it('allows to set the initial proportion', async () => {
    expect(await witch.setInitialOffer(1))
      .to.emit(witch, 'InitialOfferSet')
      .withArgs(1)
    expect(await witch.initialOffer()).to.equal(1)
  })

  it('allows to set the auction duration', async () => {
    expect(await witch.setDuration(1))
      .to.emit(witch, 'DurationSet')
      .withArgs(1)
    expect(await witch.duration()).to.equal(1)
  })

  it('allows to set the dust level', async () => {
    expect(await witch.setDust(1))
      .to.emit(witch, 'DustSet')
      .withArgs(1)
    expect(await witch.dust()).to.equal(1)
  })

  it('does not allow to auction collateralized vaults', async () => {
    await expect(witch.auction(vaultId)).to.be.revertedWith('Not undercollateralized')
  })

  it('does not allow to auction uninitialized vaults', async () => {
    await expect(witch.auction(mockVaultId)).to.be.revertedWith('Vault not found')
  })

  it('does not allow to buy from uninitialized vaults', async () => {
    await expect(witch.buy(mockVaultId, 0, 0)).to.be.revertedWith('Nothing to buy')
  })

  it('auctions undercollateralized vaults', async () => {
    await spotSource.set(WAD.div(2))
    await witch.auction(vaultId)
    const event = (await witch.queryFilter(witch.filters.Auctioned(null, null)))[0]
    expect((await cauldron.vaults(vaultId)).owner).to.equal(witch.address)
    expect((await witch.auctions(vaultId)).owner).to.equal(owner)
    expect(event.args.start.toNumber()).to.be.greaterThan(0)
    expect((await witch.auctions(vaultId)).start).to.equal(event.args.start)
  })

  describe('once a vault has been auctioned', async () => {
    beforeEach(async () => {
      await spotSource.set(WAD.div(2))
      await witch.auction(vaultId)
    })

    it("it can't be auctioned again", async () => {
      await expect(witch.auction(vaultId)).to.be.revertedWith('Vault already under auction')
    })

    it('does not buy if minimum collateral not reached', async () => {
      await expect(witch.buy(vaultId, WAD, WAD)).to.be.revertedWith('Not enough bought')
    })

    it('it can buy no collateral (coverage)', async () => {
      expect(await witch.buy(vaultId, 0, 0))
        .to.emit(witch, 'Bought')
        .withArgs(owner, vaultId, 0, 0)
    })

    it('allows to buy 1/2 of the collateral for the whole debt at the beginning', async () => {
      const baseBalanceBefore = await base.balanceOf(owner)
      const ilkBalanceBefore = await ilk.balanceOf(owner)
      await expect(witch.buy(vaultId, WAD, 0))
        .to.emit(witch, 'Bought')
        .withArgs(vaultId, owner, (await ilk.balanceOf(owner)).sub(ilkBalanceBefore), WAD)
        .to.emit(cauldron, 'VaultGiven')
        .withArgs(vaultId, owner)

      const ink = WAD.sub((await cauldron.balances(vaultId)).ink)
      expect(ink.div(10 ** 15)).to.equal(WAD.div(10 ** 15).div(2)) // Nice hack to compare up to some precision
      expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(WAD))
      expect(await ilk.balanceOf(owner)).to.equal(ilkBalanceBefore.add(ink))
      expect((await cauldron.vaults(vaultId)).owner).to.equal(owner) // The vault was returned once all the debt was paid off
    })

    it('does not buy if leaving dust', async () => {
      await witch.setDust(WAD)
      await expect(witch.buy(vaultId, WAD, 0)).to.be.revertedWith('Leaves dust')
    })

    describe('once the auction time has passed', async () => {
      beforeEach(async () => {
        const { timestamp } = await ethers.provider.getBlock('latest')
        await ethers.provider.send('evm_mine', [timestamp + (await witch.duration())])
      })

      it('allows to buy all of the collateral for the whole debt at the end', async () => {
        const baseBalanceBefore = await base.balanceOf(owner)
        const ilkBalanceBefore = await ilk.balanceOf(owner)
        await expect(witch.buy(vaultId, WAD, 0)).to.emit(witch, 'Bought').withArgs(vaultId, owner, WAD, WAD)

        const ink = WAD.sub((await cauldron.balances(vaultId)).ink)
        expect(ink).to.equal(WAD)
        expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(WAD))
        expect(await ilk.balanceOf(owner)).to.equal(ilkBalanceBefore.add(ink))
      })

      describe('after maturity, with a rate increase', async () => {
        beforeEach(async () => {
          await ethers.provider.send('evm_mine', [(await fyToken.maturity()).toNumber()])
          await cauldron.mature(seriesId)
          const rate = await cauldron.ratesAtMaturity(seriesId)
          await rateSource.set(rate.mul(110).div(100))
        })

        it('debt to repay grows with rate after maturity', async () => {
          const baseBalanceBefore = await base.balanceOf(owner)
          const ilkBalanceBefore = await ilk.balanceOf(owner)
          await expect(witch.buy(vaultId, WAD, 0))
            .to.emit(witch, 'Bought')
            .withArgs(
              vaultId,
              owner,
              WAD.sub((await cauldron.balances(vaultId)).art),
              WAD.sub((await cauldron.balances(vaultId)).ink)
            )

          const art = WAD.sub((await cauldron.balances(vaultId)).art)
          const ink = WAD.sub((await cauldron.balances(vaultId)).ink)
          expect(art).to.equal(WAD.mul(100).div(110)) // The rate increased by a 10%, so by paying WAD base we only repay 100/110 of the debt in fyToken terms
          expect(ink).to.equal(WAD.mul(100).div(110)) // We only pay 100/110 of the debt, so we get 100/110 of the collateral
          expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(WAD))
          expect(await ilk.balanceOf(owner)).to.equal(ilkBalanceBefore.add(ink))
        })

        it('allows to pay all of the debt', async () => {
          const baseBalanceBefore = await base.balanceOf(owner)
          const ilkBalanceBefore = await ilk.balanceOf(owner)
          await expect(witch.payAll(vaultId, WAD)).to.emit(witch, 'Bought').withArgs(vaultId, owner, WAD, WAD)

          expect((await cauldron.balances(vaultId)).art).to.equal(0)
          expect((await cauldron.balances(vaultId)).ink).to.equal(0)
          expect(await base.balanceOf(owner)).to.equal(baseBalanceBefore.sub(WAD.mul(110).div(100)))
          expect(await ilk.balanceOf(owner)).to.equal(ilkBalanceBefore.add(WAD))
        })
      })
    })
  })
})
