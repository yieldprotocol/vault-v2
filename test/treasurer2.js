const Treasurer = artifacts.require('./Treasurer');
const YToken = artifacts.require('./yToken');
const MockContract = artifacts.require("./MockContract")
const Oracle= artifacts.require("./Oracle")
const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');


contract('Treasurer', async (accounts) =>  {
    let TreasurerInstance;
    let owner = accounts[0];

    beforeEach('setup and deploy OracleMock', async() => {
        TreasurerInstance = await Treasurer.new(
          owner,
          web3.utils.toWei("1.5"),
          web3.utils.toWei("1.05")
        );
        OracleMock = await MockContract.new()
        await TreasurerInstance.setOracle(OracleMock.address);
    });

    describe("issue()", () => {

        it("should issue a new yToken", async() => {

        });

        it("should refuse to issue a new yToken with old maturity date", async() => {
        });

    });


    describe("addCollateral()", () => {

        it("should accept WETH collateral", async() => {
            
        });

        it("should accept CHAI collateral", async() => {
            
        });

        it("should accept Dai<>yDai Uniswap LP collateral", async() => {
            
        });

        it("should accept Chai<>yDai Uniswap LP collateral", async() => {
            
        });

        it("should accept Dai<>yDai Balancer LP collateral", async() => {
            
        });

        it("should accept Chai<>yDai Balancer LP collateral", async() => {
            
        });

        it("should fail if collateral not transfered", async() => {
        });

    });

    describe("withdrawCollateral()", () => {

        it("should fail if insufficient collateral", async() => {
        });

        it("should withdraw WETH collateral", async() => {
            
        });

        it("should withdraw CHAI collateral", async() => {
            
        });

        it("should withdraw Dai<>yDai Uniswap LP collateral", async() => {
            
        });

        it("should withdraw Chai<>yDai Uniswap LP collateral", async() => {
            
        });

        it("should withdraw Dai<>yDai Balancer LP collateral", async() => {
            
        });

        it("should withdraw Chai<>yDai Balancer LP collateral", async() => {
            
        });

        it("should fail to withdraw if undercollateralized", async() => {
        });

        it("should refuse to permit collateral withdrawl if undercollateralized", async() => {
        });
    });

    describe("borrow()", () => {

        it("should allow borrowing of yTokens", async() => {

        });

        it("should fail to borrow with insufficient collateral", async() => {
        });

        it("should fail to borrow if series does not exist", async() => {
        });

        it("should fail to borrow after maturity", async() => {
        });

    });


    describe("repay()", () => {

        it("should allow repaying debt with yTokens", async() => {

        });

        it("should fail if yToken balance is less than requested to repay", async() => {

        });

        it("should fail if yTokens provided greater than debt", async() => {

        });

        it("should fail if yToken series does not exist", async() => {

        });

        it("should allow repayment of debt after maturity", async() => {

        });

    });

    describe("repay()", () => {

        it("should allow repaying debt with yTokens", async() => {

        });

        it("should fail if yToken balance is less than requested to repay", async() => {

        });

        it("should fail if yTokens provided is greater than debt", async() => {

        });

        it("should fail if yToken series does not exist", async() => {

        });

        it("should allow repayment of debt after maturity", async() => {

        });

    });

    describe("repayUnderlying()", () => {

        it("should allow repaying debt with underlying", async() => {

        });

        it("should fail if underlying balance is less than requested to repay", async() => {

        });

        it("should fail if underlying provided is greater than debt", async() => {

        });

        it("should fail if yToken series does not exist", async() => {

        });

    });

    describe("liquidate()", () => {

        it("should allow liquidations of undercollateralized vaults", async() => {

        });

        it("should fail liquidations of sufficiently collateralized vaults", async() => {

        });

        it("should fail liquidation of non-existant vaults", async() => {

        });

    });

    describe("finalize()", () => {
    });

    describe("mature()", () => {

        it("should allow maturation of a yToken series", async() => {

        });

        it("should fail maturation if maturation time not reached", async() => {

        });

        it("should fail liquidation of non-existant vaults", async() => {

        });

    });
    

    describe("redeem()", () => {

        it("redeem yTokens for underlying", async() => {

        });

        it("should fail if yTokens not mature", async() => {

        });

        it("should fail if requested redemption exceeds balance", async() => {

        });

        it("should fail if series does not exist", async() => {

        });

    });


});