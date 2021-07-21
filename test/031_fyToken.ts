import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { constants, id } from '@yield-protocol/utils-v2'
const { WAD } = constants
import { CHI } from '../src/constants'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { CompoundMultiOracle } from '../typechain/CompoundMultiOracle'
import { ISourceMock } from '../typechain/ISourceMock'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'
import { LadleWrapper } from '../src/ladleWrapper'

describe('FYToken', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let owner: string
  let cauldron: Cauldron
  let fyToken: FYToken
  let base: ERC20Mock
  let baseJoin: Join
  let chiOracle: CompoundMultiOracle
  let chiSource: ISourceMock
  let ladle: LadleWrapper

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
  const ilkId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  const seriesId = ethers.utils.hexlify(ethers.utils.randomBytes(6))
  let vaultId: string

  beforeEach(async () => {
    env = await loadFixture(fixture)
    cauldron = env.cauldron
    ladle = env.ladle
    base = env.assets.get(baseId) as ERC20Mock
    baseJoin = env.joins.get(baseId) as Join
    fyToken = env.series.get(seriesId) as FYToken
    chiOracle = (env.oracles.get(CHI) as unknown) as CompoundMultiOracle
    chiSource = (await ethers.getContractAt('ISourceMock', await chiOracle.sources(baseId, CHI))) as ISourceMock

    await baseJoin.grantRoles([id('join(address,uint128)'), id('exit(address,uint128)')], fyToken.address)
    await baseJoin.grantRoles([id('join(address,uint128)'), id('exit(address,uint128)')], owner)

    await fyToken.grantRoles(
      [id('mint(address,uint256)'), id('burn(address,uint256)'), id('setOracle(address)')],
      owner
    )

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
    await ladle.pour(vaultId, owner, WAD, WAD) // This gives `owner` WAD fyToken

    await base.approve(baseJoin.address, WAD.mul(2))
    await baseJoin.join(owner, WAD.mul(2)) // This loads the base join to serve redemptions
  })

  it('allows to change the chi oracle', async () => {
    const mockAddress = owner
    expect(await fyToken.setOracle(mockAddress))
      .to.emit(fyToken, 'OracleSet')
      .withArgs(mockAddress)
    expect(await fyToken.oracle()).to.equal(mockAddress)
  })

  it('does not allow to mature before maturity', async () => {
    await expect(fyToken.mature()).to.be.revertedWith('Only after maturity')
  })

  it('does not allow to redeem before maturity', async () => {
    await expect(fyToken.redeem(owner, WAD)).to.be.revertedWith('Only after maturity')
  })

  describe('after maturity', async () => {
    beforeEach(async () => {
      await ethers.provider.send('evm_mine', [(await fyToken.maturity()).toNumber()])
    })

    it('does not allow to mint after maturity', async () => {
      await expect(fyToken.mint(owner, WAD)).to.be.revertedWith('Only before maturity')
    })

    it('does not allow to mature more than once', async () => {
      await fyToken.mature()
      await expect(fyToken.mature()).to.be.revertedWith('Already matured')
    })

    it('matures by recording the chi value', async () => {
      expect(await fyToken.mature())
        .to.emit(fyToken, 'SeriesMatured')
        .withArgs(WAD)
    })

    it('matures if needed on first redemption after maturity', async () => {
      const baseOwnerBefore = await base.balanceOf(owner)
      const baseJoinBefore = await base.balanceOf(baseJoin.address)
      expect(await fyToken.redeem(owner, WAD))
        .to.emit(fyToken, 'Redeemed')
        .withArgs(owner, owner, WAD, WAD)
      expect(await base.balanceOf(baseJoin.address)).to.equal(baseJoinBefore.sub(WAD))
      expect(await base.balanceOf(owner)).to.equal(baseOwnerBefore.add(WAD))
      expect(await fyToken.balanceOf(owner)).to.equal(0)
    })

    describe('once matured', async () => {
      const accrual = WAD.mul(110).div(100) // accrual is 10%

      beforeEach(async () => {
        await fyToken.mature()
        await chiSource.set(accrual) // Since spot was 1 when recorded at maturity, accrual is equal to the current spot
      })

      it("chi accrual can't be below 1", async () => {
        await chiSource.set(WAD.mul(100).div(110))
        expect(await fyToken.callStatic.accrual()).to.equal(WAD)
      })

      it('redeems fyToken for underlying according to the chi accrual', async () => {
        const baseOwnerBefore = await base.balanceOf(owner)
        const baseJoinBefore = await base.balanceOf(baseJoin.address)
        await expect(fyToken.redeem(owner, WAD))
          .to.emit(fyToken, 'Redeemed')
          .withArgs(owner, owner, WAD, WAD.mul(accrual).div(WAD))
        expect(await base.balanceOf(baseJoin.address)).to.equal(baseJoinBefore.sub(WAD.mul(accrual).div(WAD)))
        expect(await base.balanceOf(owner)).to.equal(baseOwnerBefore.add(WAD.mul(accrual).div(WAD)))
        expect(await fyToken.balanceOf(owner)).to.equal(0)
      })

      it('redeems fyToken by transferring to the fyToken contract', async () => {
        const baseOwnerBefore = await base.balanceOf(owner)
        const baseJoinBefore = await base.balanceOf(baseJoin.address)
        await fyToken.transfer(fyToken.address, WAD)
        expect(await fyToken.balanceOf(owner)).to.equal(0)
        await expect(fyToken.redeem(owner, WAD))
          .to.emit(fyToken, 'Transfer')
          .withArgs(fyToken.address, '0x0000000000000000000000000000000000000000', WAD)
          .to.emit(fyToken, 'Redeemed')
          .withArgs(owner, owner, WAD, WAD.mul(accrual).div(WAD))
        expect(await base.balanceOf(baseJoin.address)).to.equal(baseJoinBefore.sub(WAD.mul(accrual).div(WAD)))
        expect(await base.balanceOf(owner)).to.equal(baseOwnerBefore.add(WAD.mul(accrual).div(WAD)))
      })

      it('redeems fyToken by a transfer and approve combination', async () => {
        const baseOwnerBefore = await base.balanceOf(owner)
        const baseJoinBefore = await base.balanceOf(baseJoin.address)
        await fyToken.transfer(fyToken.address, WAD.div(2))
        expect(await fyToken.balanceOf(owner)).to.equal(WAD.div(2))
        await expect(fyToken.redeem(owner, WAD))
          .to.emit(fyToken, 'Transfer')
          .withArgs(fyToken.address, '0x0000000000000000000000000000000000000000', WAD.div(2))
          .to.emit(fyToken, 'Transfer')
          .withArgs(owner, '0x0000000000000000000000000000000000000000', WAD.div(2))
          .to.emit(fyToken, 'Redeemed')
          .withArgs(owner, owner, WAD, WAD.mul(accrual).div(WAD))
        expect(await base.balanceOf(baseJoin.address)).to.equal(baseJoinBefore.sub(WAD.mul(accrual).div(WAD)))
        expect(await base.balanceOf(owner)).to.equal(baseOwnerBefore.add(WAD.mul(accrual).div(WAD)))
      })

      it('redeems fyToken by transferring to the fyToken contract in a batch', async () => {
        const baseOwnerBefore = await base.balanceOf(owner)
        const baseJoinBefore = await base.balanceOf(baseJoin.address)

        await fyToken.approve(ladle.address, WAD)

        await expect(
          await ladle.batch([ladle.transferToFYTokenAction(seriesId, WAD), ladle.redeemAction(seriesId, owner, WAD)])
        )
          .to.emit(fyToken, 'Transfer')
          .withArgs(owner, fyToken.address, WAD)
          .to.emit(fyToken, 'Transfer')
          .withArgs(fyToken.address, '0x0000000000000000000000000000000000000000', WAD)
          .to.emit(fyToken, 'Redeemed')
          .withArgs(ladle.address, owner, WAD, WAD.mul(accrual).div(WAD))
        expect(await base.balanceOf(baseJoin.address)).to.equal(baseJoinBefore.sub(WAD.mul(accrual).div(WAD)))
        expect(await base.balanceOf(owner)).to.equal(baseOwnerBefore.add(WAD.mul(accrual).div(WAD)))
      })
    })
  })
})
