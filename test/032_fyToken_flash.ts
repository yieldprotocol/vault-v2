import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address'

import FlashBorrowerArtifact from '../artifacts/contracts/mocks/FlashBorrower.sol/FlashBorrower.json'

import { FYToken } from '../typechain/FYToken'
import { FlashBorrower } from '../typechain/FlashBorrower'

import { ethers, waffle } from 'hardhat'
import { expect } from 'chai'
const { deployContract, loadFixture } = waffle
const timeMachine = require('ether-time-traveler')
const MAX = ethers.constants.MaxUint256

import { YieldEnvironment, WAD } from './shared/fixtures'

describe('FYToken - flash', function () {
  this.timeout(0)
  
  let snapshotId: any
  let env: YieldEnvironment
  let ownerAcc: SignerWithAddress
  let owner: string
  let fyToken: FYToken
  let borrower: FlashBorrower

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

  beforeEach(async () => {
    env = await loadFixture(fixture)
    fyToken = env.series.get(seriesId) as FYToken
    borrower = (await deployContract(ownerAcc, FlashBorrowerArtifact, [fyToken.address])) as FlashBorrower
  })

  it('should do a simple flash loan', async () => {
    await borrower.flashBorrow(fyToken.address, WAD)

    expect(await fyToken.balanceOf(owner)).to.equal(0)
    expect(await borrower.flashBalance()).to.equal(WAD)
    expect(await borrower.flashToken()).to.equal(fyToken.address)
    expect(await borrower.flashAmount()).to.equal(WAD)
    expect(await borrower.flashInitiator()).to.equal(borrower.address)
  })

  /*
  it('can not flash loan to an EOA', async () => {
    const mockData = ethers.utils.hexlify(ethers.utils.randomBytes(32));
    await expect(fyToken.flashLoan(owner, fyToken.address, WAD, mockData)).to.be.revertedWith('Non-compliant borrower')
  })*/

  it('the receiver needs to approve the repayment if not the initiator', async () => {
    const dataSteal = '0x0000000000000000000000000000000000000000000000000000000000000001'
    await expect(fyToken.flashLoan(borrower.address, fyToken.address, WAD, dataSteal)).to.be.revertedWith(
      'ERC20: Insufficient approval'
    )
  })

  it('needs to have enough funds to repay a flash loan', async () => {
    await expect(borrower.flashBorrowAndSteal(fyToken.address, WAD)).to.be.revertedWith('ERC20: Insufficient balance')
  })

  it('should do two nested flash loans', async () => {
    await borrower.flashBorrowAndReenter(fyToken.address, WAD) // It will borrow WAD, and then reenter and borrow WAD * 2
    expect(await borrower.flashBalance()).to.equal(WAD.mul(3))
  })
})
