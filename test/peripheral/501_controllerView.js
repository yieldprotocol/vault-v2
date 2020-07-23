const ControllerView = artifacts.require("ControllerView")
const helper = require('ganache-time-traveler');
const { BN } = require('@openzeppelin/test-helpers');
const { WETH, rate1, daiTokens1: daiTokens, toWad, wethTokens1: wethTokens, addBN, subBN, toRay, divRay, mulRay } = require('./../shared/utils');
const { setupMaker, newTreasury, newController, newYDai, getDai } = require("./../shared/fixtures");

contract('ControllerView', async (accounts) =>  {
    let [ owner, user1, user2, user3 ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let jug;
    let pot;
    let chai;
    let treasury;
    let yDai1;
    let yDai2;
    let controller;
    let controllerView;

    let snapshot;
    let snapshotId;

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


        treasury = await newTreasury();
        controller = await newController();

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai1 = await newYDai(maturity1, "Name1", "Symbol1");
        yDai2 = await newYDai(maturity2, "Name2", "Symbol2");
        rate = rate1;

         // Setup ControllerView
        controllerView = await ControllerView.new(
            vat.address,
            pot.address,
            controller.address,
            { from: owner },
        );
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("allows users to post weth", async() => {
        await weth.deposit({ from: user1, value: wethTokens });
        await weth.approve(treasury.address, wethTokens, { from: user1 });
        await controller.post(WETH, user1, user1, wethTokens, { from: user1 });

        assert.equal(
            await controllerView.powerOf(WETH, user1),
            daiTokens.toString(),
            "User1 should have " + daiTokens + " borrowing power, instead has " + await controllerView.powerOf(WETH, user1),
        );
        assert.equal(
            await controllerView.locked(WETH, user1),
            0,
            "User1 should have no locked collateral, instead has " + await controllerView.locked(WETH, user1),
        );
        assert.equal(
            await controllerView.posted(WETH, user1),
            wethTokens.toString(),
            "User1 should have " + wethTokens + " weth posted, instead has " + await controllerView.posted(WETH, user1),
        );
    });

    describe("with posted weth", () => {
        beforeEach(async() => {
            await weth.deposit({ from: user1, value: wethTokens });
            await weth.approve(treasury.address, wethTokens, { from: user1 });
            await controller.post(WETH, user1, user1, wethTokens, { from: user1 });

            await weth.deposit({ from: user2, value: wethTokens });
            await weth.approve(treasury.address, wethTokens, { from: user2 });
            await controller.post(WETH, user2, user2, wethTokens, { from: user2 });
        });

        it("allows to borrow yDai", async() => {
            await controller.borrow(WETH, maturity1, user1, user1, daiTokens, { from: user1 });

            assert.equal(
                await controllerView.debtDai(WETH, maturity1, user1),
                daiTokens.toString(),
                "User1 should have debt",
            );
            assert.equal(
                await controllerView.locked(WETH, user1),
                wethTokens.toString(),
                "User1 should have " + wethTokens + " locked collateral, instead has " + await controllerView.locked(WETH, user1),
            );
            assert.equal(
                await controllerView.totalDebtYDai(WETH, maturity1),
                daiTokens.toString(), // Dai == yDai before maturity
                "System should have debt",
            );
        });

        describe("with borrowed yDai", () => {
            beforeEach(async() => {
                await controller.borrow(WETH, maturity1, user1, user1, daiTokens, { from: user1 });
                await controller.borrow(WETH, maturity1, user2, user2, daiTokens, { from: user2 });
            });

            it("allows to borrow from a second series", async() => {
                await weth.deposit({ from: user1, value: wethTokens });
                await weth.approve(treasury.address, wethTokens, { from: user1 });
                await controller.post(WETH, user1, user1, wethTokens, { from: user1 });
                await controller.borrow(WETH, maturity2, user1, user1, daiTokens, { from: user1 });

                assert.equal(
                    await controllerView.debtDai(WETH, maturity1, user1),
                    daiTokens.toString(),
                    "User1 should have debt for series 1",
                );
                assert.equal(
                    await controllerView.debtDai(WETH, maturity2, user1),
                    daiTokens.toString(),
                    "User1 should have debt for series 2",
                );
                assert.equal(
                    await controllerView.totalDebtDai(WETH, user1),
                    addBN(daiTokens, daiTokens).toString(),
                    "User1 should have a combined debt",
                );
                assert.equal(
                    await controllerView.totalDebtYDai(WETH, maturity1),
                    daiTokens.mul(2).toString(), // Dai == yDai before maturity
                    "System should have debt",
                );
            });

            describe("with borrowed yDai from two series", () => {
                beforeEach(async() => {
                    await weth.deposit({ from: user1, value: wethTokens });
                    await weth.approve(treasury.address, wethTokens, { from: user1 });
                    await controller.post(WETH, user1, user1, wethTokens, { from: user1 });
                    await controller.borrow(WETH, maturity2, user1, user1, daiTokens, { from: user1 });

                    await weth.deposit({ from: user2, value: wethTokens });
                    await weth.approve(treasury.address, wethTokens, { from: user2 });
                    await controller.post(WETH, user2, user2, wethTokens, { from: user2 });
                    await controller.borrow(WETH, maturity2, user2, user2, daiTokens, { from: user2 });
                });

                // Set rate to 1.5
                let rateIncrease;
                let rateDifferential;
                let increasedDebt;
                let debtIncrease;
    
                describe("after maturity, with a rate increase", () => {
                    beforeEach(async() => {
                        // Set rate to 1.5
                        rateIncrease = toRay(0.25);
                        rateDifferential = divRay(rate.add(rateIncrease), rate);
                        rate = rate.add(rateIncrease);
                        increasedDebt = mulRay(daiTokens, rateDifferential);
                        debtIncrease = subBN(increasedDebt, daiTokens);

                        assert.equal(
                            await yDai1.balanceOf(user1),
                            daiTokens.toString(),
                            "User1 does not have yDai",
                        );
                        assert.equal(
                            await controller.debtDai.call(WETH, maturity1, user1),
                            daiTokens.toString(),
                            "User1 does not have debt",
                        );
                        // yDai matures
                        await helper.advanceTime(1000);
                        await helper.advanceBlock();
                        await yDai1.mature();
    
                        await vat.fold(WETH, vat.address, rateIncrease, { from: owner });
                    });
    
                    it("as rate increases after maturity, so does the debt in when measured in dai", async() => {
                        assert.equal(
                            await controllerView.debtDai(WETH, maturity1, user1),
                            increasedDebt.toString(),
                            "User1 should have " + increasedDebt + " debt after the rate change, instead has " + (await controller.debtDai.call(WETH, maturity1, user1)),
                        );
                    });
        
                    it("as rate increases after maturity, the debt doesn't in when measured in yDai", async() => {
                        let debt = await controllerView.debtDai(WETH, maturity1, user1);
                        assert.equal(
                            await controller.inYDai.call(WETH, maturity1, debt),
                            daiTokens.sub(1).toString(), // 1 wei rounding error. TODO: Ensure that the error doesn't get bigger
                            "User1 should have " + daiTokens + " debt after the rate change, instead has " + (await controller.inYDai.call(WETH, maturity1, debt)),
                        );
                    });

                    it("the yDai required to repay doesn't change after maturity as rate increases", async() => {
                        await yDai1.approve(treasury.address, daiTokens, { from: user1 });
                        await controller.repayYDai(WETH, maturity1, user1, user1, daiTokens, { from: user1 });

                        assert.equal(
                            await controllerView.debtDai(WETH, maturity1, user1),
                            0,
                            "User1 should have no dai debt, instead has " + (await controller.debtDai.call(WETH, maturity1, user1)),
                        );
                    });

                    it("more Dai is required to repay after maturity as rate increases", async() => {
                        await getDai(user1, daiTokens, rate); // daiTokens is not going to be enough anymore
                        await dai.approve(treasury.address, daiTokens, { from: user1 });
                        await controller.repayDai(WETH, maturity1, user1, user1, daiTokens, { from: user1 });
            
                        assert.equal(
                            await controllerView.debtDai(WETH, maturity1, user1),
                            debtIncrease.add(1).toString(), // 1 wei rounding error. TODO: Ensure that the error doesn't get bigger
                            "User1 should have " + debtIncrease + " dai debt, instead has " + (await controller.debtDai.call(WETH, maturity1, user1)),
                        );
                    });
                });
            });
        });
    });
});
