const Treasury = artifacts.require('./Treasury');
const MockTreasury = artifacts.require('./MockTreasury');
const MockContract = artifacts.require("./MockContract")
const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');


contract('Treasury', async (accounts) =>  {
    let TreasuryInstance;
    let owner = accounts[0];

    beforeEach('setup and deploy OracleMock', async() => {
        TreasuryInstance = await Treasury.new();
    });

    describe("post()", () => {

        it("should fail for failed weth transfers", async() => {
            // Let's check how WETH is implemented, maybe we can remove this one.
        });

        it("should fail if not authorized", async() => {
            // No need to test this one, it's tested in the imported repo.
            // We will test in the contract factory that the permissions are give to the right accounts.
        });

        it("should transfer amount of WETH from user", async() => {
            // Merge with test below.
        });

        it("should send amount of WETH to ETHJoin", async() => {
            // Unless we break `post` into two functions, this is covered with the test above.
            // The EthJoin mock contract needs to have a `join` function that authorizes Vat for incoming weth transfers.
            // The EthJoin mock contract needs to have a function to return it's weth balance.
        });

        it("should call frob", async() => {
            // Wouldn't `frob` fail if `join` isn't called beforehand?
            // The Vat mock contract needs to have a frob function that takes `dink` weth from user to EthJoin
        });


    });

    describe("withdraw()", () => {

        it("should fail if not authorized", async() => {
            // No need to test this one, it's tested in the imported repo.
            // We will test in the contract factory that the permissions are give to the right accounts.
        });

        it("should withdraw amount of token", async() => {
            // Meaning the user and vault balances are modified.
            // The EthJoin mock contract needs to have an `exit` function that transfers weth to user.
            // The Vat mock contract needs to have a frob function that authorizes outgoing `wethJoin.exit` weth transfers through the `dink` parameter
        });
    });

    describe("repay()", () => {

        it("should fail if not authorized", async() => {
            // No need to test this one, it's tested in the imported repo.
            // We will test in the contract factory that the permissions are give to the right accounts.
        });

        it("should fail for failed dai transfers", async() => {
            // Let's check how DAI is implemented, maybe we can remove this one.
        });

        it("should transfer amount of Dai from source", async() => {
            // Unless we break `repay` into two functions, this is covered by the tests below.
        });

        it("should payback debt first", async() => {
            // Test `repayDai()` and `lockDai()` first
            // Test with `normalizedDebt == amount`
            // dai contract can be a standard ERC20
        });

        it("if no debt, should lock Dai in DSR ", async() => {
            // Test with `normalizedDebt == 0 && amount > 0`
            // Test with `normalizedDebt > 0 && amount > normalizedDebt`
        });
    });

    describe("disburse()", () => {

        it("should fail if not authorized", async() => {
            // No need to test this one, it's tested in the imported repo.
            // We will test in the contract factory that the permissions are give to the right accounts.
        });

        it("if DSR balance is equal or greater than amount, withdraw from DSR", async() => {
            // Test `_borrowDai()` and `_freeDai` first
            // Test with `balance == amount`
            // Mock Pot contract needs a `setChi()` and `chi()` functions.
            // Mock Pie contract needs a `setPie()` and `pie()` functions.
        });

        it("if DSR balance is not equal or greater than amount, borrow from Maker", async() => {
            // Test with `balance == 0 && amount > 0`
            // Test with `balance > 0 && amount > balance`
        });

        it("should transfer to the receiver", async() => {
            // Unless we break `disburse` into two functions, this is covered by the tests above.
        });
    });
});

contract('Treasury Internal Functions', async (accounts) =>  {
    let TreasuryInstance;
    let owner = accounts[0];

    beforeEach('setup and deploy OracleMock', async() => {
        TreasuryInstance = await MockTreasury.new();
    });

    describe("_borrowDai()", () => {

        it("should call vat correctly", async() => {
            // Isn't this covered by the test below?
        });

        it("should transfer funds from daiJoin", async() => {
            // Test with two different stability rates, if possible.
            // Mock Vat contract needs a `setRate` and an `ilks` functions.
            // Mock Vat contract needs the `frob` function to authorize `daiJoin.exit` transfers through the `dart` parameter.
        });
    });

    describe("_repayDai()", () => {

        it("should transfer funds from daiJoin", async() => {
            // This should be covered by the test below.
        });      
        
        it("should call vat correctly", async() => {
            // Test `normalizedAmount >= normalizedDebt`
            // Test `normalizedAmount < normalizedDebt`
            // Mock Vat contract needs to return `normalizedDebt` with a `urns` function
            // The DaiJoin mock contract needs to have a `join` function that authorizes Vat for incoming dai transfers.
            // The DaiJoin mock contract needs to have a function to return it's dai balance.
            // The Vat mock contract needs to have a frob function that takes `dart` dai from user to DaiJoin
        });

    });

    describe("_lockDai()", () => {

        it("should call pot.join", async() => {
            // Covered by test below.
        });

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
