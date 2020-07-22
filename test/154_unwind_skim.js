const { chi1: chi, rate1: rate, daiDebt, CHAI, WETH, daiTokens1: daiTokens, wethTokens1: wethTokens, chaiTokens1: chaiTokens, spot, toRay, mulRay, divRay } = require('./shared/utils');
const { setupMaker, newTreasury, newController, newYDai, newUnwind, newLiquidations, getChai, postChai, postWeth } = require("./shared/fixtures");
const helper = require('ganache-time-traveler');
const { expectRevert } = require('@openzeppelin/test-helpers');

contract('Unwind - Skim', async (accounts) =>  {
    let [ owner, user1, user2 ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let jug;
    let pot;
    let end;
    let chai;
    let treasury;
    let yDai1;
    let yDai2;
    let controller;
    let liquidations;
    let ethProxy;
    let unwind;

    let snapshot;
    let snapshotId;

    const THREE_MONTHS = 7776000;
    let maturity1;
    let maturity2;

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
            chai,
            end,
        } = await setupMaker());
        await vat.hope(daiJoin.address, { from: owner });

        treasury = await newTreasury();
        await treasury.orchestrate(owner, { from: owner });
        controller = await newController();

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai1 = await newYDai(maturity1, "Name1", "Symbol1");
        yDai2 = await newYDai(maturity2, "Name2", "Symbol2");

        // Setup Liquidations
        liquidations = await newLiquidations();

        // Setup Unwind
        unwind = await newUnwind();
        await yDai1.orchestrate(unwind.address);
        await yDai2.orchestrate(unwind.address);

        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });
        await end.rely(owner, { from: owner });       // `owner` replaces MKR governance
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("does not allow to skim before startSkim", async() => {
        await expectRevert(
            unwind.skimWhileLive(user1, { from: owner }),
            "Unwind: Only after skimStart",
        );
    });

    describe("three months after the expiration of the last maturity", () => {
        beforeEach(async() => {
            await helper.advanceTime(THREE_MONTHS + 2000);
            await helper.advanceBlock();
        });

        describe("with chai savings", () => {
            beforeEach(async() => {
                await getChai(owner, chaiTokens.mul(10), chi, rate);
                await chai.transfer(treasury.address, chaiTokens.mul(10), { from: owner });
                // profit = 10 chai
            });

            it("chai savings are added to profits", async() => {
                await unwind.skimWhileLive(user1, { from: owner });

                assert.equal(
                    await chai.balanceOf(user1),
                    chaiTokens.mul(10).toString(),
                    'User1 should have ' + chaiTokens.mul(10).toString() + ' chai wei',
                );
            });

            it("chai held as collateral doesn't count as profits", async() => {
                await getChai(user2, chaiTokens, chi, rate);
                await chai.approve(treasury.address, chaiTokens, { from: user2 });
                await controller.post(CHAI, user2, user2, chaiTokens, { from: user2 });

                await unwind.skimWhileLive(user1, { from: owner });

                assert.equal(
                    await chai.balanceOf(user1),
                    chaiTokens.mul(10).toString(),
                    'User1 should have ' + chaiTokens.mul(10).toString() + ' chai wei',
                );
                // profit = 10 chai
            });

            it("unredeemed yDai and controller weth debt cancel each other", async() => {
                await postWeth(user2, wethTokens);
                await controller.borrow(WETH, await yDai1.maturity(), user2, user2, daiTokens, { from: user2 }); // controller debt assets == yDai liabilities 

                await unwind.skimWhileLive(user1, { from: owner });

                assert.equal(
                    await chai.balanceOf(user1),
                    chaiTokens.mul(10).toString(),
                    'User1 should have ' + chaiTokens.mul(10).toString() + ' chai wei',
                );
                // profit = 10 chai
            });

            it("unredeemed yDai and controller chai debt cancel each other", async() => {
                await postChai(user2, chaiTokens, chi, rate);
                await controller.borrow(CHAI, await yDai1.maturity(), user2, user2, daiTokens, { from: user2 }); // controller debt assets == yDai liabilities 

                await unwind.skimWhileLive(user1, { from: owner });

                assert.equal(
                    await chai.balanceOf(user1),
                    chaiTokens.mul(10).toString(),
                    'User1 should have ' + chaiTokens.mul(10).toString() + ' chai wei',
                );
                // profit = 10 chai
            });

            describe("with dai debt", () => {
                beforeEach(async() => {
                    await treasury.pullDai(owner, daiTokens, { from: owner });
                    // profit = 9 chai
                });
        
                it("dai debt is deduced from profits", async() => {
                    await unwind.skimWhileLive(user1, { from: owner });
        
                    assert.equal(
                        await chai.balanceOf(user1),
                        chaiTokens.mul(9).toString(),
                        'User1 should have ' + chaiTokens.mul(9).toString() + ' chai wei',
                    );
                });
            });

            describe("after maturity, with a rate increase", () => {
                // Set rate to 1.5
                const rateIncrease = toRay(0.25);
                const rate0 = rate;
                const rate1 = rate.add(rateIncrease);

                const rateDifferential = divRay(rate1, rate0);

                beforeEach(async() => {
                    await postWeth(user2, wethTokens);
                    await controller.borrow(WETH, await yDai1.maturity(), user2, user2, daiTokens, { from: user2 }); // controller debt assets == yDai liabilities 

                    await postChai(user2, chaiTokens, chi, rate);
                    await controller.borrow(CHAI, await yDai1.maturity(), user2, user2, daiTokens, { from: user2 }); // controller debt assets == yDai liabilities 
                    // profit = 10 chai

                    // yDai matures
                    // await helper.advanceTime(1000);
                    // await helper.advanceBlock();
                    await yDai1.mature();

                    await vat.fold(WETH, vat.address, rateIncrease, { from: owner });
                    // profit = 10 chai + 1 chai * (rate1/rate0 - 1)
                });

                it("there is an extra profit only from weth debt", async() => {
                    await unwind.skimWhileLive(user1, { from: owner });

                    const expectedProfit = chaiTokens.mul(10).add(mulRay(chaiTokens, rateDifferential.sub(toRay(1))));
        
                    assert.equal(
                        await chai.balanceOf(user1),
                        expectedProfit.toString(),
                        'User1 should have ' + expectedProfit.toString() + ' chai wei, instead has ' + (await chai.balanceOf(user1)),
                    );
                });
            });

            describe("after maturity, with a rate increase", () => {
                // Set rate to 1.5
                const rateIncrease = toRay(0.25);
                const rate0 = rate;
                const rate1 = rate.add(rateIncrease);
                const rate2 = rate1.add(rateIncrease);

                const rateDifferential1 = divRay(rate2, rate0);
                const rateDifferential2 = divRay(rate2, rate1);

                beforeEach(async() => {
                    await postWeth(user2, wethTokens);
                    await controller.borrow(WETH, await yDai1.maturity(), user2, user2, daiTokens, { from: user2 }); // controller debt assets == yDai liabilities 

                    await postWeth(user2, wethTokens);
                    await controller.borrow(WETH, await yDai2.maturity(), user2, user2, daiTokens, { from: user2 }); // controller debt assets == yDai liabilities 

                    await postChai(user2, chaiTokens, chi, rate);
                    await controller.borrow(CHAI, await yDai1.maturity(), user2, user2, daiTokens, { from: user2 }); // controller debt assets == yDai liabilities 
                    // profit = 10 chai

                    // yDai1 matures
                    // await helper.advanceTime(1000);
                    // await helper.advanceBlock();
                    await yDai1.mature();

                    await vat.fold(WETH, vat.address, rateIncrease, { from: owner });

                    // profit = 10 chai + 1 chai * (rate1/rate0 - 1)

                    // yDai2 matures
                    // await helper.advanceTime(2000);
                    // await helper.advanceBlock();
                    await yDai2.mature();

                    await vat.fold(WETH, vat.address, rateIncrease, { from: owner });
                    // profit = 10 chai + 1 chai * (rate2/rate0 - 1) + 1 chai * (rate2/rate1 - 1)
                });

                it("profit is acummulated from several series", async() => {
                    await unwind.skimWhileLive(user1, { from: owner });

                    const expectedProfit = chaiTokens.mul(10)
                        .add(mulRay(chaiTokens, rateDifferential1.sub(toRay(1)))) // yDai1
                        .add(mulRay(chaiTokens, rateDifferential2.sub(toRay(1)))) // yDai2
                        .sub(1); // Rounding somewhere
        
                    assert.equal(
                        await chai.balanceOf(user1),
                        expectedProfit.toString(),
                        'User1 should have ' + expectedProfit.toString() + ' chai wei, instead has ' + (await chai.balanceOf(user1)),
                    );
                });
            });
        });
    });
});
