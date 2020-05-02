const Treasury = artifacts.require('./Treasury');
const MockTreasury = artifacts.require('./MockTreasury');
const MockContract = artifacts.require("./MockContract")
const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const Vat= artifacts.require('./Vat');
const GemJoin = artifacts.require('./GemJoin');
const ERC20 = artifacts.require("./TestERC20");


contract('Treasury', async (accounts) =>  {
    let TreasuryInstance;
    let [ owner, user ] = accounts;
    let vat;
    let collateral;
    let ilk = web3.utils.fromAscii("collateral")
    let Line = web3.utils.fromAscii("Line")
    let spot = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")

    const ray  = "1000000000000000000000000000";
    const supply = web3.utils.toWei("1000");
    const rad = web3.utils.toBN('49')
    const limits =  web3.utils.toBN('10').pow(rad).toString();
    // console.log(limits);

    beforeEach('setup and deploy OracleMock', async() => {
        // Set up vat, join and collateral
        vat = await Vat.new();

        collateral = await ERC20.new(supply, { from: owner }); 
        await vat.init(ilk, { from: owner });
        collateralJoin = await GemJoin.new(vat.address, ilk, collateral.address, { from: owner });

        await vat.file(ilk, spot,    ray, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?

        await vat.rely(vat.address, { from: owner });
        await vat.rely(collateralJoin.address, { from: owner });
        // await collateralJoin.join(owner, supply);

        TreasuryInstance = await Treasury.new();
    });

    describe("post()", () => {

        it("should fail for failed weth transfers", async() => {
            // Let's check how WETH is implemented, maybe we can remove this one.
        });

        it("should transfer amount of WETH from user", async() => {
            // Merge with test below.
        });

        it("should send amount of WETH from user to ETHJoin", async() => {
            // The EthJoin mock contract needs to have a `join` function that authorizes Vat for incoming weth transfers.
            // The EthJoin mock contract needs to have a function to return it's weth balance.
        });

        it("should call frob", async() => {
            // Wouldn't `frob` fail if `join` isn't called beforehand?
            // The Vat mock contract needs to have a frob function that takes `dink` weth from user to EthJoin
        });

    });

    describe("withdraw()", () => {

        it("should withdraw amount of token", async() => {
            // Meaning the user and vault balances are modified.
            // The EthJoin mock contract needs to have an `exit` function that transfers weth to user.
            // The Vat mock contract needs to have a frob function that authorizes outgoing `wethJoin.exit` weth transfers through the `dink` parameter
        });
    });

    describe("repay()", () => {

        it("should fail for failed dai transfers", async() => {
            // Let's check how DAI is implemented, maybe we can remove this one.
        });

        it("should payback debt first", async() => {
            // Dai is transferred from user
            // Test `repayDai()` and `lockDai()` first
            // Test with `normalizedDebt == amount`
            // dai contract can be a standard ERC20
        });

        it("if no debt, should lock Dai in DSR ", async() => {
            // Dai is transferred from user
            // Test with `normalizedDebt == 0 && amount > 0`
            // Test with `normalizedDebt > 0 && amount > normalizedDebt`
        });
    });

    describe("disburse()", () => {

        it("if DSR balance is equal or greater than amount, withdraw from DSR", async() => {
            // Test `_borrowDai()` and `_freeDai` first
            // Test with `balance == amount`
            // Mock Pot contract needs a `setChi()` and `chi()` functions.
            // Mock Pie contract needs a `setPie()` and `pie()` functions.
            // Transfer Dai to the user
        });

        it("if DSR balance is not equal or greater than amount, borrow from Maker", async() => {
            // Test with `balance == 0 && amount > 0`
            // Test with `balance > 0 && amount > balance`
            // Transfer Dai to the user
        });
    });

    describe("_borrowDai()", () => {

        it("should transfer funds from daiJoin", async() => {
            // Test with two different stability rates, if possible.
            // Mock Vat contract needs a `setRate` and an `ilks` functions.
            // Mock Vat contract needs the `frob` function to authorize `daiJoin.exit` transfers through the `dart` parameter.
        });
    });

    describe("_repayDai()", () => {

        it("should repay Dai borrowed from the vat", async() => {
            // Test `normalizedAmount >= normalizedDebt`
            // Test `normalizedAmount < normalizedDebt`
            // Mock Vat contract needs to return `normalizedDebt` with a `urns` function
            // The DaiJoin mock contract needs to have a `join` function that authorizes Vat for incoming dai transfers.
            // The DaiJoin mock contract needs to have a function to return it's dai balance.
            // The Vat mock contract needs to have a frob function that takes `dart` dai from user to DaiJoin
            // Should transfer funds from daiJoin
        });

    });

    describe("_lockDai()", () => {

        it("should transfer all Dai into pot.join", async() => {
            // Test with dai.balanceOf(address(this)) > 0 && pot.chi() != 1
            // The mock Pot contract should inherit from ERC20 and `join` should be a pre-approved `transferFrom`
        });

    });

    describe("_freeDai()", () => {

        it("should request normalized amount Dai from DSR", async() => {
            // Test with amount > 0 && pot.chi() != 1
            // The mock Pot contract should inherit from ERC20 and `exit` should be a `transfer`
        });

    });
});