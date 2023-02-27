const FlashLender = artifacts.require('FlashLender')
const ERC20Mock = artifacts.require('ERC20Mock')
const FlashBorrower = artifacts.require('FlashBorrower')

const { BN, expectRevert } = require('@openzeppelin/test-helpers')
require('chai').use(require('chai-as-promised')).should()

const MAX = '115792089237316195423570985008687907853269984665640564039457584007913129639935'

contract('FlashLender', (accounts) => {
  const [deployer, user1] = accounts
  let weth, dai
  let lender
  let borrower

  beforeEach(async () => {
    weth = await ERC20Mock.new("WETH", "WETH")
    dai = await ERC20Mock.new("DAI", "DAI")
    lender = await FlashLender.new([weth.address, dai.address], 10)
    borrower = await FlashBorrower.new(lender.address)

    await weth.mint(lender.address, 1000)
    await dai.mint(lender.address, 999)
  })

  it('should do a simple flash loan', async () => {
    await borrower.flashBorrow(weth.address, 1, { from: user1 })

    let balanceAfter = await weth.balanceOf(user1)
    balanceAfter.toString().should.equal(new BN('0').toString())
    let flashBalance = await borrower.flashBalance()
    flashBalance.toString().should.equal(new BN('1').toString())
    let flashToken = await borrower.flashToken()
    flashToken.toString().should.equal(weth.address)
    let flashAmount = await borrower.flashAmount()
    flashAmount.toString().should.equal(new BN('1').toString())
    let flashInitiator = await borrower.flashInitiator()
    flashInitiator.toString().should.equal(borrower.address)

    await borrower.flashBorrow(dai.address, 3, { from: user1 })

    balanceAfter = await dai.balanceOf(user1)
    balanceAfter.toString().should.equal(new BN('0').toString())
    flashBalance = await borrower.flashBalance()
    flashBalance.toString().should.equal(new BN('3').toString())
    flashToken = await borrower.flashToken()
    flashToken.toString().should.equal(dai.address)
    flashAmount = await borrower.flashAmount()
    flashAmount.toString().should.equal(new BN('3').toString())
    flashInitiator = await borrower.flashInitiator()
    flashInitiator.toString().should.equal(borrower.address)
  })

  it('should do a loan that pays fees', async () => {
    const loan = new BN('1000')
    const fee = await lender.flashFee(weth.address, loan)

    await weth.mint(borrower.address, 1, { from: user1 })
    await borrower.flashBorrow(weth.address, loan, { from: user1 })

    const balanceAfter = await weth.balanceOf(user1)
    balanceAfter.toString().should.equal(new BN('0').toString())
    const flashBalance = await borrower.flashBalance()
    flashBalance.toString().should.equal(loan.add(fee).toString())
    const flashToken = await borrower.flashToken()
    flashToken.toString().should.equal(weth.address)
    const flashAmount = await borrower.flashAmount()
    flashAmount.toString().should.equal(loan.toString())
    const flashFee = await borrower.flashFee()
    flashFee.toString().should.equal(fee.toString())
    const flashInitiator = await borrower.flashInitiator()
    flashInitiator.toString().should.equal(borrower.address)
  })

  it('needs to return funds after a flash loan', async () => {
    await expectRevert(
      borrower.flashBorrowAndSteal(weth.address, 1),
      'ERC20: insufficient-approval'
    )
  })

  it('should do two nested flash loans', async () => {
    await borrower.flashBorrowAndReenter(weth.address, 1)

    const flashBalance = await borrower.flashBalance()
    flashBalance.toString().should.equal('3')
  })
})
