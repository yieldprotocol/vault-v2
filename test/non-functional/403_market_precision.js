const YieldMathMock = artifacts.require('YieldMathMock');

const truffleAssert = require('truffle-assertions');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');
const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');

contract('Market', async (accounts) =>  {
    let yieldMath;

    const limits =  toRad(10000);
    const spot = toRay(1.2);

    const rate1 = toRay(1.4);
    const chi1 = toRay(1.2);
    const rate2 = toRay(1.82);
    const chi2 = toRay(1.5);

    const oneToken =             '1000000000000000000';
    const yDaiReserves = '112000000000000000000000000';
    const daiReserves = '134400000000000000000000000';

    const oneYear = '31556952';
    const k = '146235604338';
    const g = '18428297329635842000';

    let timeTillMaturity;

    const results = new Set();
    results.add(['trade', 'daiReserves', 'yDaiReserves', 'tokensIn', 'tokensOut']);

    beforeEach(async() => {
        // Setup YieldMathMock
        yieldMath = await YieldMathMock.new();
    });

    describe("using values from the library", () => {
        beforeEach(async() => {
            trade = oneToken;
            timeTillMaturity = oneYear;
        });

        it("sells dai", async() => {
            for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
                let yDaiOut = await yieldMath.yDaiOutForDaiIn(
                    daiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    g,
                );
    
                results.add(['sellDai128', daiReserves, yDaiReserves, trade, yDaiOut]);

                yDaiOut = await yieldMath.yDaiOutForDaiIn64(
                    daiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    g,
                );

                results.add(['sellDai64', daiReserves, yDaiReserves, trade, yDaiOut]);

                yDaiOut = await yieldMath.yDaiOutForDaiIn48(
                    daiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    g,
                );

                results.add(['sellDai48', daiReserves, yDaiReserves, trade, yDaiOut]);
            }
        });

        it("buys dai", async() => {
            for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
                let yDaiIn = await yieldMath.yDaiInForDaiOut(
                    daiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    g,
                );

                results.add(['buyDai128', daiReserves, yDaiReserves, yDaiIn, trade]);

                yDaiIn = await yieldMath.yDaiInForDaiOut64(
                    daiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    g,
                );

                results.add(['buyDai64', daiReserves, yDaiReserves, yDaiIn, trade]);

                yDaiIn = await yieldMath.yDaiInForDaiOut48(
                    daiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    g,
                );

                results.add(['buyDai64', daiReserves, yDaiReserves, yDaiIn, trade]);
            };
        });

        it("sells yDai", async() => {
            for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
                let daiOut = await yieldMath.daiOutForYDaiIn(
                    daiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    g,
                );

                results.add(['sellDai128', daiReserves, yDaiReserves, trade, daiOut]);

                daiOut = await yieldMath.daiOutForYDaiIn64(
                    daiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    g,
                );

                results.add(['sellDai64', daiReserves, yDaiReserves, trade, daiOut]);

                daiOut = await yieldMath.daiOutForYDaiIn48(
                    daiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    g,
                );

                results.add(['sellDai48', daiReserves, yDaiReserves, trade, daiOut]);
            };
        });

        it("buys yDai", async() => {
            for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
                let daiIn = await yieldMath.daiInForYDaiOut(
                    daiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    g,
                );

                results.add(['buyDai128', daiReserves, yDaiReserves, daiIn, trade]);

                daiIn = await yieldMath.daiInForYDaiOut64(
                    daiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    g,
                );

                results.add(['buyDai64', daiReserves, yDaiReserves, daiIn, trade]);

                daiIn = await yieldMath.daiInForYDaiOut48(
                    daiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    g,
                );

                results.add(['buyDai48', daiReserves, yDaiReserves, daiIn, trade]);
            };
        });
        
        it("prints results", async() => {
            for (line of results.values()) {
                console.log("| " + 
                    line[0].padEnd(12, ' ') + "· " +
                    line[1].toString().padEnd(30, ' ') + "· " +
                    line[2].toString().padEnd(30, ' ') + "· " +
                    line[3].toString().padEnd(30, ' ') + "· " +
                    line[4].toString().padEnd(30, ' ') + "|");
            }
        });
    });
});