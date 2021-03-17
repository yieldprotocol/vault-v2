import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'
import { id } from '@yield-protocol/utils'

import { Cauldron } from '../typechain/Cauldron'
import { Join } from '../typechain/Join'
import { FYToken } from '../typechain/FYToken'
import { ERC20Mock } from '../typechain/ERC20Mock'
import { OracleMock } from '../typechain/OracleMock'
import { Ladle } from '../typechain/Ladle'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle
const timeMachine = require('ether-time-traveler')

import { YieldEnvironment, WAD, RAY, THREE_MONTHS } from './shared/fixtures'

describe('FYToken', function () {
  this.timeout(0)
  
  let snapshotId: any
  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let owner: string
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
    snapshotId = await timeMachine.takeSnapshot(ethers.provider) // `loadFixture` messes up with the chain state, so we revert to a clean state after each test file.
    const signers = await ethers.getSigners()
    ownerAcc = signers[0]
    owner = await ownerAcc.getAddress()
  })

  after(async () => {
    await timeMachine.revertToSnapshot(ethers.provider, snapshotId) // Once all tests are done, revert the chain
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

    await baseJoin.grantRoles([id('join(address,int128)')], fyToken.address)

    await fyToken.grantRoles([id('mint(address,uint256)'), id('burn(address,uint256)')], owner)

    vaultId = (env.vaults.get(seriesId) as Map<string, string>).get(ilkId) as string
    await ladle.pour(vaultId, owner, WAD, WAD) // This gives `owner` WAD fyToken
    await base.transfer(baseJoin.address, WAD.mul(2)) // This loads the base join to serve redemptions
  })

  it('does not allow to mature before maturity', async () => {
    await expect(fyToken.mature()).to.be.revertedWith('Record after maturity')
  })

  it('does not allow to redeem before maturity', async () => {
    await expect(fyToken.redeem(owner, WAD)).to.be.revertedWith('Not mature')
  })

  describe('after maturity', async () => {
    beforeEach(async () => {
      await timeMachine.advanceTimeAndBlock(ethers.provider, THREE_MONTHS)
    })

    it('matures by recording the chi value', async () => {
      const maturity = await fyToken.maturity()
      expect(await fyToken.mature())
        .to.emit(chiOracle, 'Recorded')
        .withArgs(maturity, RAY)
    })

    it('does not allow to mature more than once', async () => {
      await fyToken.mature()
      await expect(fyToken.mature()).to.be.revertedWith('Already recorded a value')
    })

    it('does not allow to redeem before chi is recorded', async () => {
      await expect(fyToken.redeem(owner, WAD)).to.be.revertedWith('No recorded spot')
    })

    describe('once matured', async () => {
      const accrual = RAY.mul(110).div(100) // accrual is 10%

      beforeEach(async () => {
        await fyToken.mature()
        await chiOracle.setSpot(accrual) // Since spot was 1 when recorded at maturity, accrual is equal to the current spot
      })

      it('redeems fyToken for underlying according to the chi accrual', async () => {
        const baseOwnerBefore = await base.balanceOf(owner)
        const baseJoinBefore = await base.balanceOf(baseJoin.address)
        await expect(fyToken.redeem(owner, WAD))
          .to.emit(fyToken, 'Redeemed')
          .withArgs(owner, owner, WAD, WAD.mul(accrual).div(RAY))
        expect(await base.balanceOf(baseJoin.address)).to.equal(baseJoinBefore.sub(WAD.mul(accrual).div(RAY)))
        expect(await base.balanceOf(owner)).to.equal(baseOwnerBefore.add(WAD.mul(accrual).div(RAY)))
        expect(await fyToken.balanceOf(owner)).to.equal(0)
      })
    })
  })
})
