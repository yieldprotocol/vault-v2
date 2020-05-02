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

contract('Treasury Internal Functions', async (accounts) =>  {
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