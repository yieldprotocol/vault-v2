const Market = artifacts.require('Market');

const { toWad, toRay, mulRay } = require('../shared/utils');
const { setupMaker, newTreasury, newController, newYDai, getDai } = require("../shared/fixtures");
const { BN, expectRevert } = require('@openzeppelin/test-helpers');
const { assert, expect } = require('chai');

contract('LimitMarket', async (accounts) =>  {
    let [ owner, user1, operator, from, to ] = accounts;
    let dai;
    let treasury;
    let yDai1;
    let controller;
    let market;

    // These values impact the market results
    const rate1 = toRay(1.4);
    const daiDebt1 = toWad(96);
    const daiTokens1 = mulRay(daiDebt1, rate1);
    const yDaiTokens1 = daiTokens1;

    let maturity1;

    beforeEach(async() => {
        ({
            vat,
            weth,
            wethJoin,
            dai,
            daiJoin,
            pot,
            jug,
            end,
            chai
        } = await setupMaker());

        treasury = await newTreasury();
        controller = await newController();

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952; // One year
        yDai1 = await newYDai(maturity1, "Name", "Symbol");

        // Setup Market
        market = await Market.new(
            dai.address,
            yDai1.address,
            { from: owner }
        );

        // Test setup

        // Allow owner to mint yDai the sneaky way, without recording a debt in controller
        await yDai1.orchestrate(owner, { from: owner });

    });

    describe("with liquidity", () => {
        beforeEach(async() => {
            const daiReserves = daiTokens1;
            await getDai(user1, daiReserves, rate1)
    
            await dai.approve(market.address, daiReserves, { from: user1 });
            await market.init(daiReserves, { from: user1 });
        });

        it("buys dai without delegation", async() => {
            const oneToken = toWad(1);
            await yDai1.mint(from, yDaiTokens1, { from: owner });

            // yDaiInForChaiOut formula: https://www.desmos.com/calculator/16c4dgxhst

            assert.equal(
                await yDai1.balanceOf(from),
                yDaiTokens1.toString(),
                "'From' wallet should have " + yDaiTokens1 + " yDai, instead has " + await yDai1.balanceOf(from),
            );

            await yDai1.approve(market.address, yDaiTokens1, { from: from });
            await market.buyDai(from, to, oneToken, { from: from });

            assert.equal(
                await dai.balanceOf(to),
                oneToken.toString(),
                "Receiver account should have 1 dai token",
            );

            const expectedYDaiIn = (new BN(oneToken.toString())).mul(new BN('10019')).div(new BN('10000')); // I just hate javascript
            const yDaiIn = (new BN(yDaiTokens1.toString())).sub(new BN(await yDai1.balanceOf(from)));
            expect(yDaiIn).to.be.bignumber.gt(expectedYDaiIn.mul(new BN('9999')).div(new BN('10000')));
            expect(yDaiIn).to.be.bignumber.lt(expectedYDaiIn.mul(new BN('10001')).div(new BN('10000')));
        });

        it("sells yDai without delegation", async() => {
            const oneToken = toWad(1);
            await yDai1.mint(from, oneToken, { from: owner });

            // chaiOutForYDaiIn formula: https://www.desmos.com/calculator/6ylefi7fv7

            assert.equal(
                await dai.balanceOf(to),
                0,
                "'To' wallet should have no dai, instead has " + await dai.balanceOf(to),
            );

            await yDai1.approve(market.address, oneToken, { from: from });
            await market.sellYDai(from, to, oneToken, { from: from });

            assert.equal(
                await yDai1.balanceOf(from),
                0,
                "'From' wallet should have no yDai tokens",
            );

            const expectedDaiOut = (new BN(oneToken.toString())).mul(new BN('99814')).div(new BN('100000')); // I just hate javascript
            const daiOut = new BN(await dai.balanceOf(to));
            expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')));
            expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')));
        });

        describe("with extra yDai reserves", () => {
            beforeEach(async() => {
                const additionalYDaiReserves = toWad(34.4);
                await yDai1.mint(operator, additionalYDaiReserves, { from: owner });
                await yDai1.approve(market.address, additionalYDaiReserves, { from: operator });
                await market.sellYDai(operator, operator, additionalYDaiReserves, { from: operator });
            });

            it("sells dai without delegation", async() => {
                const oneToken = toWad(1);
                await getDai(from, daiTokens1, rate1);
    
                // yDaiOutForChaiIn formula: https://www.desmos.com/calculator/dcjuj5lmmc
    
                assert.equal(
                    await yDai1.balanceOf(to),
                    0,
                    "'To' wallet should have no yDai, instead has " + await yDai1.balanceOf(operator),
                );
    
                await dai.approve(market.address, oneToken, { from: from });
                await market.sellDai(from, to, oneToken, { from: from });
    
                assert.equal(
                    await dai.balanceOf(from),
                    daiTokens1.sub(oneToken).toString(),
                    "'From' wallet should have " + daiTokens1.sub(oneToken) + " dai tokens",
                );
    
                const expectedYDaiOut = (new BN(oneToken.toString())).mul(new BN('1132')).div(new BN('1000')); // I just hate javascript
                const yDaiOut = new BN(await yDai1.balanceOf(to));
                // TODO: Test precision with 48 and 64 bits with this trade and reserve levels
                expect(yDaiOut).to.be.bignumber.gt(expectedYDaiOut.mul(new BN('999')).div(new BN('1000')));
                expect(yDaiOut).to.be.bignumber.lt(expectedYDaiOut.mul(new BN('1001')).div(new BN('1000')));
            });

            it("buys yDai without delegation", async() => {
                const oneToken = toWad(1);
                await getDai(from, daiTokens1, rate1);

                // chaiInForYDaiOut formula: https://www.desmos.com/calculator/cgpfpqe3fq

                assert.equal(
                    await yDai1.balanceOf(to),
                    0,
                    "'To' wallet should have no yDai, instead has " + await yDai1.balanceOf(to),
                );

                await dai.approve(market.address, daiTokens1, { from: from });
                await market.buyYDai(from, to, oneToken, { from: from });

                assert.equal(
                    await yDai1.balanceOf(to),
                    oneToken.toString(),
                    "'To' wallet should have 1 yDai token",
                );

                const expectedDaiIn = (new BN(oneToken.toString())).mul(new BN('8835')).div(new BN('10000')); // I just hate javascript
                const daiIn = (new BN(daiTokens1.toString())).sub(new BN(await dai.balanceOf(from)));
                expect(daiIn).to.be.bignumber.gt(expectedDaiIn.mul(new BN('9999')).div(new BN('10000')));
                expect(daiIn).to.be.bignumber.lt(expectedDaiIn.mul(new BN('10001')).div(new BN('10000')));
            });
        });

        // --- ONLY HOLDER OR DELEGATE TESTS ---

        it("doesn't sell dai without delegation", async() => {
            await expectRevert(
                market.sellDai(from, to, 1, { from: operator }),
                "Market: Only Holder Or Delegate",
            );
        });

        it("doesn't buy dai without delegation", async() => {
            await expectRevert(
                market.buyDai(from, to, 1, { from: operator }),
                "Market: Only Holder Or Delegate",
            );
        });

        it("doesn't sell yDai without delegation", async() => {
            await expectRevert(
                market.sellYDai(from, to, 1, { from: operator }),
                "Market: Only Holder Or Delegate",
            );
        });

        it("doesn't buy yDai without delegation", async() => {
            await expectRevert(
                market.buyYDai(from, to, 1, { from: operator }),
                "Market: Only Holder Or Delegate",
            );
        });
    });
});