import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id } from '@yield-protocol/utils'
import { WAD, DEC6, OPS } from './shared/constants'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { OracleMock } from '../typechain/OracleMock'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'

describe('FYToken', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let owner: string
  let other: string
  let cauldron: Cauldron
  let fyToken: FYToken
  let base: ERC20Mock
  let baseJoin: Join
  let chiOracle: OracleMock
  let ladle: Ladle

  async function fixture() {
    return await YieldEnvironment.setup(ownerAcc, [baseId, ilkId], [seriesId])
  }

  before(async () => {
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
    other = await signers[1].getAddress()
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
    chiOracle = env.oracles.get('chi') as OracleMock

    await baseJoin.grantRoles([id('join(address,uint128)'), id('exit(address,uint128)')], fyToken.address)

    await fyToken.grantRoles(
      [id('mint(address,uint256)'), id('burn(address,uint256)'), id('setParameter(bytes32,bytes32)')],
      owner
    )

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
    await ladle.pour(vaultId, owner, WAD, WAD) // This gives `owner` WAD fyToken

    await base.approve(baseJoin.address, WAD.mul(2))
    await baseJoin.join(owner, WAD.mul(2)) // This loads the base join to serve redemptions
  })

  it.only('mints a fee to the beneficiary', async () => {
    const feeId = ethers.utils.formatBytes32String('fee')
    const beneficiaryId = ethers.utils.formatBytes32String('beneficiary')
    const wrongId = ethers.utils.formatBytes32String('wrong')
    const oneBytes32 = '0x0000000000000000000000000000000000000000000000000000000000000001'
    const otherBytes32 = (other + '000000000000000000000000').toLowerCase()

    await expect(fyToken.setParameter(feeId, oneBytes32)).to.emit(fyToken, 'ParameterSet').withArgs(feeId, oneBytes32)
    await expect(fyToken.setParameter(beneficiaryId, otherBytes32))
      .to.emit(fyToken, 'ParameterSet')
      .withArgs(beneficiaryId, otherBytes32)
    await expect(fyToken.setParameter(wrongId, oneBytes32)).to.be.revertedWith('Unrecognized parameter')

    await fyToken.mint(owner, WAD)
    expect(await fyToken.balanceOf(other)).to.not.equal(0)
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
      await expect(fyToken.mature()).to.be.revertedWith('Already recorded a value')
    })

    it('does not allow to redeem before chi is recorded', async () => {
      await expect(fyToken.redeem(owner, WAD)).to.be.revertedWith('No recorded spot')
    })

    it('matures by recording the chi value', async () => {
      const maturity = await fyToken.maturity()
      expect(await fyToken.mature())
        .to.emit(chiOracle, 'Recorded')
        .withArgs(maturity, DEC6)
    })

    describe('once matured', async () => {
      const accrual = DEC6.mul(110).div(100) // accrual is 10%

      beforeEach(async () => {
        await fyToken.mature()
        await chiOracle.setSpot(accrual) // Since spot was 1 when recorded at maturity, accrual is equal to the current spot
      })

      it('redeems fyToken for underlying according to the chi accrual', async () => {
        const baseOwnerBefore = await base.balanceOf(owner)
        const baseJoinBefore = await base.balanceOf(baseJoin.address)
        await expect(fyToken.redeem(owner, WAD))
          .to.emit(fyToken, 'Redeemed')
          .withArgs(owner, owner, WAD, WAD.mul(accrual).div(DEC6))
        expect(await base.balanceOf(baseJoin.address)).to.equal(baseJoinBefore.sub(WAD.mul(accrual).div(DEC6)))
        expect(await base.balanceOf(owner)).to.equal(baseOwnerBefore.add(WAD.mul(accrual).div(DEC6)))
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
          .withArgs(owner, owner, WAD, WAD.mul(accrual).div(DEC6))
        expect(await base.balanceOf(baseJoin.address)).to.equal(baseJoinBefore.sub(WAD.mul(accrual).div(DEC6)))
        expect(await base.balanceOf(owner)).to.equal(baseOwnerBefore.add(WAD.mul(accrual).div(DEC6)))
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
          .withArgs(owner, owner, WAD, WAD.mul(accrual).div(DEC6))
        expect(await base.balanceOf(baseJoin.address)).to.equal(baseJoinBefore.sub(WAD.mul(accrual).div(DEC6)))
        expect(await base.balanceOf(owner)).to.equal(baseOwnerBefore.add(WAD.mul(accrual).div(DEC6)))
      })

      it('redeems fyToken by transferring to the fyToken contract in a batch', async () => {
        const baseOwnerBefore = await base.balanceOf(owner)
        const baseJoinBefore = await base.balanceOf(baseJoin.address)

        await fyToken.approve(ladle.address, WAD)
        const transferToFYTokenData = ethers.utils.defaultAbiCoder.encode(['uint256'], [WAD])
        const redeemData = ethers.utils.defaultAbiCoder.encode(['address', 'uint128'], [owner, WAD])

        await expect(
          await ladle.batch(vaultId, [OPS.TRANSFER_TO_FYTOKEN, OPS.REDEEM], [transferToFYTokenData, redeemData])
        )
          .to.emit(fyToken, 'Transfer')
          .withArgs(owner, fyToken.address, WAD)
          .to.emit(fyToken, 'Transfer')
          .withArgs(fyToken.address, '0x0000000000000000000000000000000000000000', WAD)
          .to.emit(fyToken, 'Redeemed')
          .withArgs(ladle.address, owner, WAD, WAD.mul(accrual).div(DEC6))
        expect(await base.balanceOf(baseJoin.address)).to.equal(baseJoinBefore.sub(WAD.mul(accrual).div(DEC6)))
        expect(await base.balanceOf(owner)).to.equal(baseOwnerBefore.add(WAD.mul(accrual).div(DEC6)))
      })
    })
  })
})
