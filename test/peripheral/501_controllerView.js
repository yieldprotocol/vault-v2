// External
const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Jug = artifacts.require('Jug');
const Pot = artifacts.require('Pot');
const End = artifacts.require('End');
const Chai = artifacts.require('Chai');

// Common
const Treasury = artifacts.require('Treasury');

// YDai
const YDai = artifacts.require('YDai');
const Controller = artifacts.require('Controller');

// Peripheral
const EthProxy = artifacts.require('EthProxy');
const Unwind = artifacts.require('Unwind');
const ControllerView = artifacts.require('ControllerView');

const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN, expectRevert } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');
const { assert } = require('chai');

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

    let WETH = web3.utils.fromAscii("ETH-A");
    let CHAI = web3.utils.fromAscii("CHAI");
    let Line = web3.utils.fromAscii("Line");
    let spotName = web3.utils.fromAscii("spot");
    let linel = web3.utils.fromAscii("line");

    let snapshot;
    let snapshotId;

    const limits = toRad(10000);
    const spot  = toRay(150);
    let rate;
    let daiDebt;
    let daiTokens;
    let wethTokens;
    let maturity1;
    let maturity2;

    // Convert eth to weth and use it to borrow `daiTokens` from MakerDAO
    // This function shadows and uses global variables, careful.
    async function getDai(user, _daiTokens){
        await vat.hope(daiJoin.address, { from: user });
        await vat.hope(wethJoin.address, { from: user });

        const _daiDebt = divRay(_daiTokens, rate);
        const _wethTokens = addBN(divRay(_daiTokens, spot), 1);

        await weth.deposit({ from: user, value: _wethTokens });
        await weth.approve(wethJoin.address, _wethTokens, { from: user });
        await wethJoin.join(user, _wethTokens, { from: user });
        await vat.frob(WETH, user, user, user, _wethTokens, _daiDebt, { from: user });
        await daiJoin.exit(user, _daiTokens, { from: user });
    }

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        rate  = toRay(1.25);
        daiDebt = toWad(120);
        daiTokens = mulRay(daiDebt, rate);
        wethTokens = divRay(daiTokens, spot);

        // Setup vat, join and weth
        vat = await Vat.new();
        await vat.init(WETH, { from: owner }); // Set WETH rate (stability fee accumulator) to 1.0

        weth = await Weth.new({ from: owner });
        wethJoin = await GemJoin.new(vat.address, WETH, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        await vat.file(WETH, spotName, spot, { from: owner });
        await vat.file(WETH, linel, limits, { from: owner });
        await vat.file(Line, limits);

        // Setup jug
        jug = await Jug.new(vat.address);
        await jug.init(WETH, { from: owner }); // Set WETH duty (stability fee) to 1.0

        // Setup pot
        pot = await Pot.new(vat.address);

        // Permissions
        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.rely(jug.address, { from: owner });
        await vat.rely(pot.address, { from: owner });
        await vat.hope(daiJoin.address, { from: owner });

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
            { from: owner },
        );

        // Set treasury
        treasury = await Treasury.new(
            vat.address,
            weth.address,
            dai.address,
            wethJoin.address,
            daiJoin.address,
            pot.address,
            chai.address,
            { from: owner },
        );

        // Setup Controller
        controller = await Controller.new(
            vat.address,
            pot.address,
            treasury.address,
            { from: owner },
        );
        treasury.orchestrate(controller.address, { from: owner });

        // Setup ControllerView
        controllerView = await ControllerView.new(
            vat.address,
            pot.address,
            controller.address,
            { from: owner },
        );

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai1 = await YDai.new(
            vat.address,
            jug.address,
            pot.address,
            treasury.address,
            maturity1,
            "Name",
            "Symbol",
            { from: owner },
        );
        controller.addSeries(yDai1.address, { from: owner });
        yDai1.orchestrate(controller.address, { from: owner });
        treasury.orchestrate(yDai1.address, { from: owner });

        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai2 = await YDai.new(
            vat.address,
            jug.address,
            pot.address,
            treasury.address,
            maturity2,
            "Name2",
            "Symbol2",
            { from: owner },
        );
        controller.addSeries(yDai2.address, { from: owner });
        yDai2.orchestrate(controller.address, { from: owner });
        treasury.orchestrate(yDai2.address, { from: owner });

        // Tests setup
        await vat.fold(WETH, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0
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
                            daiTokens.toString(),
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
                        await getDai(user1, daiTokens); // daiTokens is not going to be enough anymore
                        await dai.approve(treasury.address, daiTokens, { from: user1 });
                        await controller.repayDai(WETH, maturity1, user1, user1, daiTokens, { from: user1 });
            
                        assert.equal(
                            await controllerView.debtDai(WETH, maturity1, user1),
                            debtIncrease.toString(),
                            "User1 should have " + debtIncrease + " dai debt, instead has " + (await controller.debtDai.call(WETH, maturity1, user1)),
                        );
                    });
                });
            });
        });
    });
});

function bytes32ToString(text) {
    return web3.utils.toAscii(text).replace(/\0/g, '');
}