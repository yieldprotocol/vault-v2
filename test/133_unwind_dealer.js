const helper = require('ganache-time-traveler');
const { expectRevert } = require('@openzeppelin/test-helpers');
const { daiDebt, CHAI, WETH, daiTokens1: daiTokens, wethTokens1: wethTokens, chaiTokens1: chaiTokens, spot, toRay, mulRay, divRay } = require('./shared/utils');
const { setupMaker, newTreasury, newController, newYDai, newUnwind, newLiquidations } = require("./shared/fixtures");

contract('Unwind - Controller', async (accounts) =>  {
    let [ owner, user1, user2, user3 ] = accounts;
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

    let maturity1;
    let maturity2;

    const tag  = divRay(toRay(1.0), spot); // Irrelevant to the final users
    const fix  = divRay(toRay(1.0), mulRay(spot, toRay(1.1)));
    const fixedWeth = mulRay(daiTokens, fix);
    const yDaiTokens = daiTokens;

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

    describe("with posted collateral and borrowed yDai", () => {
        beforeEach(async() => {
            // Weth setup
            await weth.deposit({ from: user1, value: wethTokens });
            await weth.approve(treasury.address, wethTokens, { from: user1 });
            await controller.post(WETH, user1, user1, wethTokens, { from: user1 });

            await weth.deposit({ from: user2, value: wethTokens.add(1) });
            await weth.approve(treasury.address, wethTokens.add(1), { from: user2 });
            await controller.post(WETH, user2, user2, wethTokens.add(1), { from: user2 });
            await controller.borrow(WETH, maturity1, user2, user2, daiTokens, { from: user2 });

            await weth.deposit({ from: user3, value: wethTokens.mul(3) });
            await weth.approve(treasury.address, wethTokens.mul(3), { from: user3 });
            await controller.post(WETH, user3, user3, wethTokens.mul(3), { from: user3 });
            await controller.borrow(WETH, maturity1, user3, user3, daiTokens, { from: user3 });
            await controller.borrow(WETH, maturity2, user3, user3, daiTokens, { from: user3 });

            // Chai setup
            await vat.hope(daiJoin.address, { from: user1 });
            await vat.hope(wethJoin.address, { from: user1 });

            await weth.deposit({ from: user1, value: wethTokens });
            await weth.approve(wethJoin.address, wethTokens, { from: user1 });
            await wethJoin.join(user1, wethTokens, { from: user1 });
            await vat.frob(WETH, user1, user1, user1, wethTokens, daiDebt, { from: user1 });
            await daiJoin.exit(user1, daiTokens, { from: user1 });
            await dai.approve(chai.address, daiTokens, { from: user1 });
            await chai.join(user1, daiTokens, { from: user1 });
            await chai.approve(treasury.address, chaiTokens, { from: user1 });
            await controller.post(CHAI, user1, user1, chaiTokens, { from: user1 });

            await vat.hope(daiJoin.address, { from: user2 });
            await vat.hope(wethJoin.address, { from: user2 });

            const moreDebt = mulRay(daiDebt, toRay(1.1));
            const moreDai = mulRay(daiTokens, toRay(1.1));
            const moreWeth = mulRay(wethTokens, toRay(1.1));
            const moreChai = mulRay(chaiTokens, toRay(1.1));
            await weth.deposit({ from: user2, value: moreWeth });
            await weth.approve(wethJoin.address, moreWeth, { from: user2 });
            await wethJoin.join(user2, moreWeth, { from: user2 });
            await vat.frob(WETH, user2, user2, user2, moreWeth, moreDebt, { from: user2 });
            await daiJoin.exit(user2, moreDai, { from: user2 });
            await dai.approve(chai.address, moreDai, { from: user2 });
            await chai.join(user2, moreDai, { from: user2 });
            await chai.approve(treasury.address, moreChai, { from: user2 });
            await controller.post(CHAI, user2, user2, moreChai, { from: user2 });
            await controller.borrow(CHAI, maturity1, user2, user2, daiTokens, { from: user2 });

            // user1 has chaiTokens in controller and no debt.
            // user2 has chaiTokens * 1.1 in controller and daiTokens debt.

            // Make sure that end.sol will have enough weth to cash chai savings
            await weth.deposit({ from: owner, value: wethTokens.mul(10) });
            await weth.approve(wethJoin.address, wethTokens.mul(10), { from: owner });
            await wethJoin.join(owner, wethTokens.mul(10), { from: owner });
            await vat.frob(WETH, owner, owner, owner, wethTokens.mul(10), daiDebt.mul(10), { from: owner });
            await daiJoin.exit(owner, daiTokens.mul(10), { from: owner });

            assert.equal(
                await weth.balanceOf(user1),
                0,
                'User1 should have no weth',
            );
            assert.equal(
                await weth.balanceOf(user2),
                0,
                'User2 should have no weth',
            );
            assert.equal(
                await controller.debtYDai(WETH, maturity1, user2),
                yDaiTokens.toString(),
                'User2 should have ' + yDaiTokens.toString() + ' maturity1 weth debt, instead has ' + (await controller.debtYDai(WETH, maturity1, user2)).toString(),
            );
        });

        it("does not allow to redeem YDai if treasury not settled and cashed", async() => {
            await expectRevert(
                unwind.redeem(maturity1, yDaiTokens, user2, { from: user2 }),
                "Unwind: Not ready",
            );
        });

        it("does not allow to settle users if treasury not settled and cashed", async() => {
            await expectRevert(
                unwind.settle(WETH, user2, { from: user2 }),
                "Unwind: Not ready",
            );
        });

        /* it("does not allow to profit if treasury not settled and cashed", async() => {
            await expectRevert(
                unwind.profit(owner, { from: user2 }),
                "Unwind: Not ready",
            );
        }); */

        describe("with Dss unwind initiated and treasury settled", () => {
            beforeEach(async() => {
                await end.cage({ from: owner });
                await end.setTag(WETH, tag, { from: owner });
                await end.setDebt(1, { from: owner });
                await end.setFix(WETH, fix, { from: owner });
                await end.skim(WETH, user1, { from: owner });
                await end.skim(WETH, user2, { from: owner });
                await end.skim(WETH, owner, { from: owner });
                await unwind.unwind({ from: owner });
                await unwind.settleTreasury({ from: owner });
                await unwind.cashSavings({ from: owner });
            });

            it("controller shuts down", async() => {
                assert.equal(
                    await controller.live.call(),
                    false,
                    'Controller should not be live',
                );
            });

            it("does not allow to post, withdraw, borrow or repay assets", async() => {
                await expectRevert(
                    controller.post(WETH, owner, owner, wethTokens, { from: owner }),
                    "Controller: Not available during unwind",
                );
                await expectRevert(
                    controller.withdraw(WETH, owner, owner, wethTokens, { from: owner }),
                    "Controller: Not available during unwind",
                );
                await expectRevert(
                    controller.borrow(WETH, maturity1, owner, owner, yDaiTokens, { from: owner }),
                    "Controller: Not available during unwind",
                );
                await expectRevert(
                    controller.repayDai(WETH, maturity1, owner, owner, daiTokens, { from: owner }),
                    "Controller: Not available during unwind",
                );
                await expectRevert(
                    controller.repayYDai(WETH, maturity1, owner, owner, yDaiTokens, { from: owner }),
                    "Controller: Not available during unwind",
                );
            });

            /* it("does not allow to profit if there is user debt", async() => {
                await expectRevert(
                    unwind.profit(owner, { from: user2 }),
                    "Unwind: Redeem all yDai",
                );
            }); */

            it("user can redeem YDai", async() => {
                await unwind.redeem(maturity1, yDaiTokens, user2, { from: user2 });

                assert.equal(
                    await weth.balanceOf(user2),
                    fixedWeth.toString(),
                    'User2 should have ' + fixedWeth.toString() + ' weth wei, instead has ' + (await weth.balanceOf(user2)).toString(),
                );
            });

            it("allows user to settle weth surplus", async() => {
                await unwind.settle(WETH, user1, { from: user1 });

                assert.equal(
                    await weth.balanceOf(user1),
                    wethTokens.toString(),
                    'User1 should have ' + wethTokens.toString() + ' weth wei',
                );
            });

            it("users can be forced to settle weth surplus", async() => {
                await unwind.settle(WETH, user1, { from: owner });

                assert.equal(
                    await weth.balanceOf(user1),
                    wethTokens.toString(),
                    'User1 should have ' + wethTokens.toString() + ' weth wei',
                );
            });

            it("allows user to settle chai surplus", async() => {
                await unwind.settle(CHAI, user1, { from: user1 });

                // Remember that chai is converted to weth when withdrawing
                assert.equal(
                    await weth.balanceOf(user1),
                    fixedWeth.toString(),
                    'User1 should have ' + fixedWeth.sub(1).toString() + ' weth wei',
                );
            });

            it("users can be forced to settle chai surplus", async() => {
                await unwind.settle(CHAI, user1, { from: owner });

                // Remember that chai is converted to weth when withdrawing
                assert.equal(
                    await weth.balanceOf(user1),
                    fixedWeth.toString(),
                    'User1 should have ' + fixedWeth.sub(1).toString() + ' weth wei',
                );
            });

            it("allows user to settle weth debt", async() => {
                await unwind.settle(WETH, user2, { from: user2 });

                assert.equal(
                    await controller.debtYDai(WETH, maturity1, user2),
                    0,
                    'User2 should have no maturity1 weth debt',
                );
                // In the tests the settling nets zero surplus, which we tested above
            });

            it("allows user to settle chai debt", async() => {
                await unwind.settle(CHAI, user2, { from: user2 });

                assert.equal(
                    await controller.debtYDai(CHAI, maturity1, user2),
                    0,
                    'User2 should have no maturity1 chai debt',
                );
                // In the tests the settling nets zero surplus, which we tested above
            });

            it("allows user to settle mutiple weth positions", async() => {
                await unwind.settle(WETH, user3, { from: user3 });

                assert.equal(
                    await weth.balanceOf(user3),
                    wethTokens.mul(3).sub(fixedWeth.mul(2)).sub(1).toString(), // Each position settled substracts daiTokens * fix from the user collateral 
                    'User1 should have ' + wethTokens.mul(3).sub(fixedWeth.mul(2)).sub(1).toString() + ' weth wei, instead has ' + (await weth.balanceOf(user3)),
                );
                // In the tests the settling nets zero surplus, which we tested above
            });

            /* describe("with all yDai redeemed", () => {
                beforeEach(async() => {
                    await unwind.redeem(maturity1, yDaiTokens.mul(2), user2, { from: user2 });
                    await unwind.redeem(maturity1, yDaiTokens, user3, { from: user3 });
                    await unwind.redeem(maturity2, yDaiTokens, user3, { from: user3 });
                });

                it("allows to extract profit", async() => {
                    const profit = await weth.balanceOf(unwind.address);

                    await unwind.profit(owner, { from: owner });
    
                    assert.equal(
                        (await weth.balanceOf(owner)).toString(),
                        profit,
                        'Owner should have ' + profit + ' weth, instead has ' + (await weth.balanceOf(owner)),
                    );
                });
            }); */
        });
    });
});
