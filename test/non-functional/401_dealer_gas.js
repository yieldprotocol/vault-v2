const helper = require('ganache-time-traveler');
const { WETH, rate1: rate, daiTokens1, wethTokens1: wethTokens1 } = require('./../shared/utils');
const { shutdown, setupMaker, newTreasury, newController, newYDai, getDai, postWeth, newUnwind, newLiquidations } = require("./../shared/fixtures");

contract('Gas Usage', async (accounts) =>  {
    let [ owner, user1, user2, user3 ] = accounts;
    let dai;
    let treasury;
    let yDai1;
    let yDai2;
    let controller;
    let liquidations;
    let unwind;

    let snapshot;
    let snapshotId;

    let maturities;
    let series;

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        ({
            vat,
            weth,
            wethJoin,
            dai,
            daiJoin,
            pot,
            jug,
            chai
        } = await setupMaker());

        treasury = await newTreasury();
        controller = await newController();
        liquidations = await newLiquidations()
        unwind = await newUnwind()

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai1 = await newYDai(maturity1, "Name", "Symbol");
        yDai2 = await newYDai(maturity2, "Name", "Symbol");
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    const m = 4; // Number of maturities to test.
    describe("working with " + m + " maturities", () => {
        beforeEach(async() => {
            // Setup yDai
            const block = await web3.eth.getBlockNumber();
            maturities = []; // Clear the registry for each test
            series = []; // Clear the registry for each test
            for (let i = 0; i < m; i++) {
                const maturity = (await web3.eth.getBlock(block)).timestamp + (i*1000); 
                maturities.push(maturity);
                series.push(await newYDai(maturity, "Name", "Symbol"));
            }
        });

        describe("post and borrow", () => {
            beforeEach(async() => {
                // Set the scenario
                
                for (let i = 0; i < maturities.length; i++) {
                    await postWeth(user3, wethTokens1);
                    await controller.borrow(WETH, maturities[i], user3, user3, daiTokens1, { from: user3 });
                }
            });

            it("borrow a second time", async() => {
                for (let i = 0; i < maturities.length; i++) {
                    await postWeth(user3, wethTokens1);
                    await controller.borrow(WETH, maturities[i], user3, user3, daiTokens1, { from: user3 });
                }
            });

            it("repayYDai", async() => {
                for (let i = 0; i < maturities.length; i++) {
                    await series[i].approve(treasury.address, daiTokens1, { from: user3 });
                    await controller.repayYDai(WETH, maturities[i], user3, user3, daiTokens1, { from: user3 });
                }
            });

            it("repay all debt with repayYDai", async() => {
                for (let i = 0; i < maturities.length; i++) {
                    await series[i].approve(controller.address, daiTokens1.mul(2), { from: user3 });
                    await controller.repayYDai(WETH, maturities[i], user3, user3, daiTokens1.mul(2), { from: user3 });
                }
            });

            it("repayDai and withdraw", async() => {
                await helper.advanceTime(m * 1000);
                await helper.advanceBlock();
                
                for (let i = 0; i < maturities.length; i++) {
                    await getDai(user3, daiTokens1, rate);
                    await dai.approve(treasury.address, daiTokens1, { from: user3 });
                    await controller.repayDai(WETH, maturities[i], user3, user3, daiTokens1, { from: user3 });
                }
                
                for (let i = 0; i < maturities.length; i++) {
                    await controller.withdraw(WETH, user3, user3, wethTokens1, { from: user3 });
                }
            });

            describe("during dss unwind", () => {
                beforeEach(async() => {
                    await shutdown(owner, user1, user2)
                });

                it("single series settle", async() => {
                    await unwind.settle(WETH, user3, { from: user3 });
                });

                it("all series settle", async() => {
                    await unwind.settle(WETH, user3, { from: user3 });
                });
            });
        });
    });
});
