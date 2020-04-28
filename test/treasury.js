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

        it("should fail if not authorized", async() => {

        });

        it("should transfer amount of WETH from user", async() => {

        });

        it("should send amount of WETH to ETHJoin", async() => {

        });

        it("should call frob", async() => {

        });


    });

    describe("withdraw()", () => {

        it("should fail if not authorized", async() => {

        });

        it("should withdraw amount of token", async() => {

        });
    });

    describe("repay()", () => {

        it("should fail if not authorized", async() => {

        });

        it("should transfer amount of Dai from source", async() => {

        });

        it("should payback debt first", async() => {

        });

        it("if no debt, should lock Dai in DSR ", async() => {

        });
    });

    describe("disburse()", () => {

        it("should fail if not authorized", async() => {

        });

        it("if DSR balance is greater than amount, withdraw from DSR", async() => {

        });

        it("if DSR balance is not greater than amount, borrow from Maker", async() => {

        });

        it("should transfer to the receiver", async() => {

        });
    });
});

contract('Treasury Private Functions', async (accounts) =>  {
    let TreasuryInstance;
    let owner = accounts[0];

    beforeEach('setup and deploy OracleMock', async() => {
        TreasuryInstance = await MockTreasury.new();
    });

    describe("_borrowDai()", () => {

        it("should call vat correctly", async() => {

        });

        it("should transfer funds from daiJoin", async() => {

        });


    });

    describe("_repayDai()", () => {

        it("should transfer funds from daiJoin", async() => {

        });      
        
        it("should call vat correctly", async() => {

        });

    });

    describe("_lockDai()", () => {

        it("should call pot.join", async() => {

        });

        it("should transfer all Dai into pot.join", async() => {

        });

    });

    describe("_freeDai()", () => {

        it("should request normalized amount Dai from DSR", async() => {

        });

    });
});