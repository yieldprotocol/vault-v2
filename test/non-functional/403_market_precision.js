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
    const chaiReserves = '134400000000000000000000000';

    const oneYear = '31556952';
    const k = '146235604338';
    const g = '18428297329635842000';
    const c = '22136092888451460000';

    let timeTillMaturity;

    const results = new Set();
    results.add(['trade', 'chaiReserves', 'yDaiReserves', 'tokensIn', 'tokensOut']);

    beforeEach(async() => {
        // Setup YieldMathMock
        yieldMath = await YieldMathMock.new();
    });

    describe("using values from the library", () => {
        beforeEach(async() => {
            trade = oneToken;
            timeTillMaturity = oneYear;
        });

        it("sells chai", async() => {
            for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
                let yDaiOut = await yieldMath.yDaiOutForChaiIn(
                    chaiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    c,
                    g,
                );
    
                results.add(['sellChai128', chaiReserves, yDaiReserves, trade, yDaiOut]);

                yDaiOut = await yieldMath.yDaiOutForChaiIn64(
                    chaiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    c,
                    g,
                );

                results.add(['sellChai64', chaiReserves, yDaiReserves, trade, yDaiOut]);

                yDaiOut = await yieldMath.yDaiOutForChaiIn48(
                    chaiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    c,
                    g,
                );

                results.add(['sellChai48', chaiReserves, yDaiReserves, trade, yDaiOut]);
            }
        });

        it("buys chai", async() => {
            for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
                let yDaiIn = await yieldMath.yDaiInForChaiOut(
                    chaiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    c,
                    g,
                );

                results.add(['buyChai128', chaiReserves, yDaiReserves, yDaiIn, trade]);

                yDaiIn = await yieldMath.yDaiInForChaiOut64(
                    chaiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    c,
                    g,
                );

                results.add(['buyChai64', chaiReserves, yDaiReserves, yDaiIn, trade]);

                yDaiIn = await yieldMath.yDaiInForChaiOut48(
                    chaiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    c,
                    g,
                );

                results.add(['buyChai64', chaiReserves, yDaiReserves, yDaiIn, trade]);
            };
        });

        it("sells yDai", async() => {
            for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
                let chaiOut = await yieldMath.chaiOutForYDaiIn(
                    chaiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    c,
                    g,
                );

                results.add(['sellChai128', chaiReserves, yDaiReserves, trade, chaiOut]);

                chaiOut = await yieldMath.chaiOutForYDaiIn64(
                    chaiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    c,
                    g,
                );

                results.add(['sellChai64', chaiReserves, yDaiReserves, trade, chaiOut]);

                chaiOut = await yieldMath.chaiOutForYDaiIn48(
                    chaiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    c,
                    g,
                );

                results.add(['sellChai48', chaiReserves, yDaiReserves, trade, chaiOut]);
            };
        });

        it("buys yDai", async() => {
            for (let trade of ['10000000000000000000', '1000000000000000000000', '1000000000000000000000000']) {
                let chaiIn = await yieldMath.chaiInForYDaiOut(
                    chaiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    c,
                    g,
                );

                results.add(['buyChai128', chaiReserves, yDaiReserves, chaiIn, trade]);

                chaiIn = await yieldMath.chaiInForYDaiOut64(
                    chaiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    c,
                    g,
                );

                results.add(['buyChai64', chaiReserves, yDaiReserves, chaiIn, trade]);

                chaiIn = await yieldMath.chaiInForYDaiOut48(
                    chaiReserves,
                    yDaiReserves,
                    trade,
                    timeTillMaturity,
                    k,
                    c,
                    g,
                );

                results.add(['buyChai48', chaiReserves, yDaiReserves, chaiIn, trade]);
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

    /* describe("with liquidity", () => {
        beforeEach(async() => {
            await getChai(user1, chaiReserves)
            await yDai1.mint(user1, yDaiReserves, { from: owner });
    
            await chai.approve(market.address, chaiReserves, { from: user1 });
            await yDai1.approve(market.address, yDaiReserves, { from: user1 });
            await market.init(chaiReserves, yDaiReserves, { from: user1 });
        });

        it("sells chai", async() => {
            const trade = toWad(1).div(1000);
            await getChai(from, chaiTokens1);

            await market.addDelegate(operator, { from: from });
            await chai.approve(market.address, trade, { from: from });
            await market.sellChai(from, to, trade, { from: operator });

            const yDaiOut = new BN(await yDai1.balanceOf(to));

            results.add(['sellChai', chaiReserves, yDaiReserves, trade, yDaiOut]);
        });

        it("buys chai", async() => {
            const trade = toWad(1).div(1000);
            await yDai1.mint(from, yDaiTokens1.div(1000), { from: owner });

            await market.addDelegate(operator, { from: from });
            await yDai1.approve(market.address, yDaiTokens1.div(1000), { from: from });
            await market.buyChai(from, to, trade, { from: operator });

            const yDaiIn = (new BN(yDaiTokens1.div(1000).toString())).sub(new BN(await yDai1.balanceOf(from)));

            results.add(['buyChai', chaiReserves, yDaiReserves, yDaiIn, trade]);
        });

        it("sells yDai", async() => {
            const trade = toWad(1).div(1000);
            await yDai1.mint(from, trade, { from: owner });

            await market.addDelegate(operator, { from: from });
            await yDai1.approve(market.address, trade, { from: from });
            await market.sellYDai(from, to, trade, { from: operator });

            const chaiOut = new BN(await chai.balanceOf(to));
            results.add(['sellYDai', chaiReserves, yDaiReserves, trade, chaiOut]);
        });

        it("buys yDai", async() => {
            const trade = toWad(1).div(1000);
            await getChai(from, chaiTokens1.div(1000));

            await market.addDelegate(operator, { from: from });
            await chai.approve(market.address, chaiTokens1.div(1000), { from: from });
            await market.buyYDai(from, to, trade, { from: operator });

            const chaiIn = (new BN(chaiTokens1.div(1000).toString())).sub(new BN(await chai.balanceOf(from)));
            results.add(['buyYDai', chaiReserves, yDaiReserves, chaiIn, trade]);
        });
    }); */
});