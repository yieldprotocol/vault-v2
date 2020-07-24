const { CHAI, WETH, spot, chi1, rate1, daiTokens1, wethTokens1, chaiTokens1, toRay, mulRay, divRay } = require('./shared/utils');
const { YieldEnvironment } = require("./shared/fixtures");
const helper = require('ganache-time-traveler');
const { expectRevert } = require('@openzeppelin/test-helpers');

contract('Unwind - DSS Skim', async (accounts) =>  {
    let [ owner, user1, user2, user3, user4 ] = accounts;

    let snapshot;
    let snapshotId;

    let maturity1;
    let maturity2;

    const fix  = divRay(toRay(1.0), mulRay(spot, toRay(1.1)));
    const fixedWeth = mulRay(daiTokens1, fix);

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        yield = await YieldEnvironment.setup(user3)
        controller = yield.controller;
        treasury = yield.treasury;
        unwind = yield.unwind;

        vat = yield.maker.vat;
        weth = yield.maker.weth;
        end = yield.maker.end;
        chai = yield.maker.chai;

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai1 = await yield.newYDai(maturity1, "Name", "Symbol");
        yDai2 = await yield.newYDai(maturity2, "Name", "Symbol");
        await yDai1.orchestrate(unwind.address)
        await yDai2.orchestrate(unwind.address)
        await treasury.orchestrate(owner)
        await end.rely(owner, { from: owner });       // `owner` replaces MKR governance
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("does not allow to settle users if treasury not settled and cashed", async() => {
        await expectRevert(
            unwind.skimDssShutdown({ from: owner }),
            "Unwind: Not ready",
        );
    });

    describe("with chai savings", () => {
        beforeEach(async() => {
            await yield.maker.getChai(owner, chaiTokens1.mul(10), chi1, rate1);
            await chai.transfer(treasury.address, chaiTokens1.mul(10), { from: owner });
            // profit = 10 dai * fix (in weth)
        });

        it("chai savings are added to profits", async() => {
            await yield.shutdown(owner, user1, user2);
            await unwind.skimDssShutdown({ from: owner });

            assert.equal(
                await weth.balanceOf(user3),
                fixedWeth.mul(10).add(8).toString(), // A few wei won't make a difference
                'User3 should have ' + fixedWeth.add(8).toString() + ' weth wei, instead has ' + (await weth.balanceOf(user3)),
            );
            // profit = 10 dai * fix (in weth)
        });

        it("chai held as collateral doesn't count as profits", async() => {
            await yield.postChai(user2, chaiTokens1, chi1, rate1);

            await yield.shutdown(owner, user1, user2);
            await unwind.skimDssShutdown({ from: owner });

            assert.equal(
                await weth.balanceOf(user3),
                fixedWeth.mul(10).add(9).toString(), // A few wei won't make a difference
                'User3 should have ' + fixedWeth.mul(10).add(9).toString() + ' weth wei, instead has ' + await weth.balanceOf(user3),
            );
            // profit = 10 dai * fix (in weth)
        });

        it("unredeemed yDai and controller weth debt cancel each other", async() => {
            await yield.postWeth(user2, wethTokens1);
            await controller.borrow(WETH, await yDai1.maturity(), user2, user2, daiTokens1, { from: user2 }); // controller debt assets == yDai liabilities 

            await yield.shutdown(owner, user1, user2);
            await unwind.skimDssShutdown({ from: owner });

            assert.equal(
                await weth.balanceOf(user3),
                fixedWeth.mul(10).add(8).toString(), // A few wei won't make a difference
                'User3 should have ' + fixedWeth.mul(10).add(8).toString() + ' weth wei, instead has ' + await weth.balanceOf(user3),
            );
            // profit = 10 dai * fix (in weth)
        });

        it("unredeemed yDai and controller chai debt cancel each other", async() => {
            await yield.postChai(user2, chaiTokens1, chi1, rate1);
            await controller.borrow(CHAI, await yDai1.maturity(), user2, user2, daiTokens1, { from: user2 }); // controller debt assets == yDai liabilities 

            await yield.shutdown(owner, user1, user2);
            await unwind.skimDssShutdown({ from: owner });

            assert.equal(
                await weth.balanceOf(user3),
                fixedWeth.mul(10).add(9).toString(), // A few wei won't make a difference
                'User3 should have ' + fixedWeth.mul(10).add(9).toString() + ' weth wei',
            );
            // profit = 10 dai * fix (in weth)
        });

        describe("with dai debt", () => {
            beforeEach(async() => {
                await treasury.pullDai(owner, daiTokens1, { from: owner });
                // profit = 9 chai
            });
    
            it("dai debt is deduced from profits", async() => {
                await yield.shutdown(owner, user1, user2);
                await unwind.skimDssShutdown({ from: owner });
    
                assert.equal(
                    await weth.balanceOf(user3),
                    fixedWeth.mul(9).add(7).toString(), // A few wei won't make a difference
                    'User3 should have ' + fixedWeth.mul(9).add(7).toString() + ' weth wei, instead has ' + (await weth.balanceOf(user3)),
                );
            });
        });

        describe("after maturity, with a rate increase", () => {
            const rateIncrease = toRay(0.25);
            const rate2 = rate1.add(rateIncrease);

            const rateDifferential = divRay(rate2, rate1);

            beforeEach(async() => {
                await yield.postWeth(user2, wethTokens1);
                await controller.borrow(WETH, await yDai1.maturity(), user2, user2, daiTokens1, { from: user2 }); // controller debt assets == yDai liabilities 

                await yield.postChai(user2, chaiTokens1, chi1, rate1);
                await controller.borrow(CHAI, await yDai1.maturity(), user2, user2, daiTokens1, { from: user2 }); // controller debt assets == yDai liabilities 
                // profit = 10 chai

                // yDai matures
                await helper.advanceTime(1000);
                await helper.advanceBlock();
                await yDai1.mature();

                await vat.fold(WETH, vat.address, rateIncrease, { from: owner });
                // profit = 10 chai + 1 chai * (rate2/rate1 - 1)
            });

            it("there is an extra profit only from weth debt", async() => {
                await yield.shutdown(owner, user1, user2);
                await unwind.skimDssShutdown({ from: owner });

                // A few wei won't make a difference
                const expectedProfit = fixedWeth.mul(10).add(mulRay(fixedWeth, rateDifferential.sub(toRay(1)))).add(9);
    
                assert.equal(
                    await weth.balanceOf(user3),
                    expectedProfit.toString(),
                    'User3 should have ' + expectedProfit.toString() + ' chai wei, instead has ' + (await weth.balanceOf(user3)),
                );
            });
        });

        describe("after maturity, with a rate increase", () => {
            const rateIncrease = toRay(0.25);
            const rate2 = rate1.add(rateIncrease);
            const rate3 = rate2.add(rateIncrease);

            const rateDifferential1 = divRay(rate3, rate1);
            const rateDifferential2 = divRay(rate3, rate2);

            beforeEach(async() => {
                await yield.postWeth(user2, wethTokens1);
                await controller.borrow(WETH, await yDai1.maturity(), user2, user2, daiTokens1, { from: user2 }); // controller debt assets == yDai liabilities 

                await yield.postWeth(user2, wethTokens1);
                await controller.borrow(WETH, await yDai2.maturity(), user2, user2, daiTokens1, { from: user2 }); // controller debt assets == yDai liabilities 

                await yield.postChai(user2, chaiTokens1, chi1, rate1);
                await controller.borrow(CHAI, await yDai1.maturity(), user2, user2, daiTokens1, { from: user2 }); // controller debt assets == yDai liabilities 
                // profit = 10 chai

                // yDai1 matures
                await helper.advanceTime(1000);
                await helper.advanceBlock();
                await yDai1.mature();

                await vat.fold(WETH, vat.address, rateIncrease, { from: owner });

                // profit = 10 chai + 1 chai * (rate2/rate1 - 1)

                // yDai2 matures
                await helper.advanceTime(2000);
                await helper.advanceBlock();
                await yDai2.mature();

                await vat.fold(WETH, vat.address, rateIncrease, { from: owner });
                // profit = 10 chai + 1 chai * (rate3/rate1 - 1) + 1 chai * (rate3/rate2 - 1)
            });

            it("profit is acummulated from several series", async() => {
                await yield.shutdown(owner, user1, user2);
                await unwind.skimDssShutdown({ from: owner });

                const expectedProfit = fixedWeth.mul(10)
                    .add(mulRay(fixedWeth, rateDifferential1.sub(toRay(1))))  // yDai1
                    .add(mulRay(fixedWeth, rateDifferential2.sub(toRay(1))))  // yDai2
                    .add(8); // A few wei won't make a difference
    
                assert.equal(
                    await weth.balanceOf(user3),
                    expectedProfit.toString(),
                    'User3 should have ' + expectedProfit.toString() + ' chai wei, instead has ' + (await weth.balanceOf(user3)),
                );
            });
        });
    });
});
