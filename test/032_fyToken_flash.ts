import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import { constants } from '@yield-protocol/utils-v2'
const { WAD } = constants

import FlashBorrowerArtifact from '../artifacts/contracts/mocks/FlashBorrower.sol/FlashBorrower.json'

import { FYToken } from '../typechain/FYToken'
import { FlashBorrower } from '../typechain/FlashBorrower'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle

import { YieldEnvironment } from './shared/fixtures'

describe('FYToken - flash', function () {
  this.timeout(0)

  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let owner: string
  let fyToken: FYToken
  let borrower: FlashBorrower

  const actions = {
    normal: '0x0000000000000000000000000000000000000000000000000000000000000000',
    transfer: '0x0000000000000000000000000000000000000000000000000000000000000001',
    steal: '0x0000000000000000000000000000000000000000000000000000000000000002',
    reenter: '0x0000000000000000000000000000000000000000000000000000000000000003',
  }

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

  beforeEach(async () => {
    env = await loadFixture(fixture)
    fyToken = env.series.get(seriesId) as FYToken
    borrower = (await deployContract(ownerAcc, FlashBorrowerArtifact, [fyToken.address])) as FlashBorrower
  })

  it('should do a simple flash loan', async () => {
    await borrower.flashBorrow(fyToken.address, WAD, actions.normal)

    expect(await fyToken.balanceOf(owner)).to.equal(0)
    expect(await borrower.flashBalance()).to.equal(WAD)
    expect(await borrower.flashToken()).to.equal(fyToken.address)
    expect(await borrower.flashAmount()).to.equal(WAD)
    expect(await borrower.flashInitiator()).to.equal(borrower.address)
  })

  it('can repay the flash loan by transfer', async () => {
    await expect(borrower.flashBorrow(fyToken.address, WAD, actions.transfer))
      .to.emit(fyToken, 'Transfer')
      .withArgs(fyToken.address, '0x0000000000000000000000000000000000000000', WAD)

    expect(await fyToken.balanceOf(owner)).to.equal(0)
    expect(await borrower.flashBalance()).to.equal(WAD)
    expect(await borrower.flashToken()).to.equal(fyToken.address)
    expect(await borrower.flashAmount()).to.equal(WAD)
    expect(await borrower.flashInitiator()).to.equal(borrower.address)
  })

  it('the receiver needs to approve the repayment if not the initiator', async () => {
    await expect(fyToken.flashLoan(borrower.address, fyToken.address, WAD, actions.normal)).to.be.revertedWith(
      'ERC20: Insufficient approval'
    )
  })

  it('needs to have enough funds to repay a flash loan', async () => {
    await expect(borrower.flashBorrow(fyToken.address, WAD, actions.steal)).to.be.revertedWith(
      'ERC20: Insufficient balance'
    )
  })

  it('should do two nested flash loans', async () => {
    await borrower.flashBorrow(fyToken.address, WAD, actions.reenter) // It will borrow WAD, and then reenter and borrow WAD * 2
    expect(await borrower.flashBalance()).to.equal(WAD.mul(3))
  })

  describe('after maturity', async () => {
    beforeEach(async () => {
      await ethers.provider.send('evm_mine', [(await fyToken.maturity()).toNumber()])
    })

    it('does not allow to flash mint after maturity', async () => {
      await expect(borrower.flashBorrow(fyToken.address, WAD, actions.normal)).to.be.revertedWith(
        'Only before maturity'
      )
    })
  })
})
