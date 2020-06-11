// External
const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const End = artifacts.require('End');
const Chai = artifacts.require('Chai');

// Common
const ChaiOracle = artifacts.require('ChaiOracle');
const WethOracle = artifacts.require('WethOracle');
const Treasury = artifacts.require('Treasury');

// YDai
const YDai = artifacts.require('YDai');
const Dealer = artifacts.require('Dealer');

// Peripheral
const Splitter = artifacts.require('MockSplitter');
const DssShutdown = artifacts.require('DssShutdown');

const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('DssShutdown - Treasury', async (accounts) =>  {
    let [ owner, user1, user2, user3, user4 ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let pot;
    let end;
    let chai;
    let chaiOracle;
    let wethOracle;
    let treasury;
    let yDai1;
    let yDai2;
    let wethDealer;
    let splitter;
    let dssShutdown;

    let WETH = web3.utils.fromAscii("WETH");
    let CHAI = web3.utils.fromAscii("CHAI");
    let ilk = web3.utils.fromAscii("ETH-A");
    let Line = web3.utils.fromAscii("Line");
    let spotName = web3.utils.fromAscii("spot");
    let linel = web3.utils.fromAscii("line");

    let snapshot;
    let snapshotId;

    const limits = toRad(10000);
    const spot  = toRay(1.5);
    const rate  = toRay(1.25);
    const chi = toRay(1.2);
    const daiDebt = toWad(120);
    const daiTokens = mulRay(daiDebt, rate);
    const wethTokens = divRay(daiTokens, spot);
    const chaiTokens = divRay(daiTokens, chi);
    const yDaiTokens = daiTokens;
    let maturity1;
    let maturity2;

    const tag  = divRay(toRay(1), spot); // TODO: Test with tag different than initial value
    const fix  = divRay(toRay(1), spot); // TODO: Test with fix different from tag

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        // Setup vat
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        weth = await Weth.new({ from: owner });
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        await vat.file(ilk, spotName, spot, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); // TODO: Why can't we specify `, { from: owner }`?
        await vat.fold(ilk, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        // Setup pot
        pot = await Pot.new(vat.address);
        await pot.setChi(chi, { from: owner });

        // Setup end
        end = await End.new({ from: owner });
        await end.file(web3.utils.fromAscii("vat"), vat.address);

        // Permissions
        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.rely(pot.address, { from: owner });
        await vat.rely(end.address, { from: owner });

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
            { from: owner },
        );

        // Setup Oracle
        wethOracle = await WethOracle.new(vat.address, { from: owner });

        // Setup ChaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });

        // Set treasury
        treasury = await Treasury.new(
            dai.address,
            chai.address,
            chaiOracle.address,
            weth.address,
            daiJoin.address,
            wethJoin.address,
            vat.address,
            { from: owner },
        );

        // Setup wethDealer
        wethDealer = await Dealer.new(
            treasury.address,
            dai.address,
            weth.address,
            wethOracle.address,
            WETH,
            { from: owner },
        );
        await treasury.grantAccess(wethDealer.address, { from: owner });

        // Setup chaiDealer
        chaiDealer = await Dealer.new(
            treasury.address,
            dai.address,
            chai.address,
            chaiOracle.address,
            CHAI,
            { from: owner },
        );
        await treasury.grantAccess(chaiDealer.address, { from: owner });

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai1 = await YDai.new(
            vat.address,
            pot.address,
            treasury.address,
            maturity1,
            "Name",
            "Symbol",
            { from: owner },
        );
        await wethDealer.addSeries(yDai1.address, { from: owner });
        await chaiDealer.addSeries(yDai1.address, { from: owner });
        await yDai1.grantAccess(wethDealer.address, { from: owner });
        await yDai1.grantAccess(chaiDealer.address, { from: owner });
        await treasury.grantAccess(yDai1.address, { from: owner });

        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai2 = await YDai.new(
            vat.address,
            pot.address,
            treasury.address,
            maturity2,
            "Name2",
            "Symbol2",
            { from: owner },
        );
        await wethDealer.addSeries(yDai2.address, { from: owner });
        await chaiDealer.addSeries(yDai2.address, { from: owner });
        await yDai2.grantAccess(wethDealer.address, { from: owner })
        await yDai2.grantAccess(chaiDealer.address, { from: owner });
        await treasury.grantAccess(yDai2.address, { from: owner });

        // Setup Splitter
        splitter = await Splitter.new(
            treasury.address,
            wethDealer.address,
            { from: owner },
        );
        await wethDealer.grantAccess(splitter.address, { from: owner });
        await treasury.grantAccess(splitter.address, { from: owner });

        // Setup DssShutdown
        dssShutdown = await DssShutdown.new(
            vat.address,
            daiJoin.address,
            weth.address,
            wethJoin.address,
            end.address,
            chai.address,
            chaiOracle.address,
            treasury.address,
            wethDealer.address,
            chaiDealer.address,
            { from: owner },
        );
        await wethDealer.grantAccess(dssShutdown.address, { from: owner });
        await chaiDealer.grantAccess(dssShutdown.address, { from: owner });
        await treasury.registerDssShutdown(dssShutdown.address, { from: owner });
        await yDai1.grantAccess(dssShutdown.address, { from: owner });
        await yDai2.grantAccess(dssShutdown.address, { from: owner });

        // Testing permissions
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });
        await treasury.grantAccess(owner, { from: owner });
        await end.rely(owner, { from: owner });       // `owner` replaces MKR governance
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    /* it("get the size of the contract", async() => {
        console.log();
        console.log("·--------------------|------------------|------------------|------------------·");
        console.log("|  Contract          ·  Bytecode        ·  Deployed        ·  Constructor     |");
        console.log("·····················|··················|··················|···················");

        const bytecode = wethDealer.constructor._json.bytecode;
        const deployed = wethDealer.constructor._json.deployedBytecode;
        const sizeOfB  = bytecode.length / 2;
        const sizeOfD  = deployed.length / 2;
        const sizeOfC  = sizeOfB - sizeOfD;
        console.log(
            "|  " + (wethDealer.constructor._json.contractName).padEnd(18, ' ') +
            "|" + ("" + sizeOfB).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfD).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfC).padStart(16, ' ') + "  |");
        console.log("·--------------------|------------------|------------------|------------------·");
        console.log();
    }); */

    it("does not attempt to settle treasury debt until Dss shutdown initiated", async() => {
        await expectRevert(
            dssShutdown.settleTreasury({ from: owner }),
            "DssShutdown: End.sol not caged",
        );
    });

    describe("with posted collateral and borrowed yDai", () => {
        beforeEach(async() => {
            // Weth setup
            await weth.deposit({ from: user1, value: wethTokens });
            await weth.approve(wethDealer.address, wethTokens, { from: user1 });
            await wethDealer.post(user1, wethTokens, { from: user1 });

            await weth.deposit({ from: user2, value: wethTokens.add(1) });
            await weth.approve(wethDealer.address, wethTokens.add(1), { from: user2 });
            await wethDealer.post(user2, wethTokens.add(1), { from: user2 });
            await wethDealer.borrow(maturity1, user2, daiTokens, { from: user2 });

            await weth.deposit({ from: user3, value: wethTokens.mul(3) });
            await weth.approve(wethDealer.address, wethTokens.mul(3), { from: user3 });
            await wethDealer.post(user3, wethTokens.mul(3), { from: user3 });
            await wethDealer.borrow(maturity1, user3, daiTokens, { from: user3 });
            await wethDealer.borrow(maturity2, user3, daiTokens, { from: user3 });

            // Chai setup
            await vat.hope(daiJoin.address, { from: user1 });
            await vat.hope(wethJoin.address, { from: user1 });

            await weth.deposit({ from: user1, value: wethTokens });
            await weth.approve(wethJoin.address, wethTokens, { from: user1 });
            await wethJoin.join(user1, wethTokens, { from: user1 });
            await vat.frob(ilk, user1, user1, user1, wethTokens, daiDebt, { from: user1 });
            await daiJoin.exit(user1, daiTokens, { from: user1 });
            await dai.approve(chai.address, daiTokens, { from: user1 });
            await chai.join(user1, daiTokens, { from: user1 });
            await chai.approve(chaiDealer.address, chaiTokens, { from: user1 });
            await chaiDealer.post(user1, chaiTokens, { from: user1 });

            await vat.hope(daiJoin.address, { from: user2 });
            await vat.hope(wethJoin.address, { from: user2 });

            const moreDebt = mulRay(daiDebt, toRay(1.1));
            const moreDai = mulRay(daiTokens, toRay(1.1));
            const moreWeth = mulRay(wethTokens, toRay(1.1));
            const moreChai = mulRay(chaiTokens, toRay(1.1));
            await weth.deposit({ from: user2, value: moreWeth });
            await weth.approve(wethJoin.address, moreWeth, { from: user2 });
            await wethJoin.join(user2, moreWeth, { from: user2 });
            await vat.frob(ilk, user2, user2, user2, moreWeth, moreDebt, { from: user2 });
            await daiJoin.exit(user2, moreDai, { from: user2 });
            await dai.approve(chai.address, moreDai, { from: user2 });
            await chai.join(user2, moreDai, { from: user2 });
            await chai.approve(chaiDealer.address, moreChai, { from: user2 });
            await chaiDealer.post(user2, moreChai, { from: user2 });
            await chaiDealer.borrow(maturity1, user2, daiTokens, { from: user2 });

            // user1 has chaiTokens in chaiDealer and no debt.
            // user2 has chaiTokens * 1.1 in chaiDealer and daiTokens debt.

            // Make sure that end.sol will have enough weth to cash chai savings
            await weth.deposit({ from: owner, value: wethTokens });
            await weth.approve(wethJoin.address, wethTokens, { from: owner });
            await wethJoin.join(owner, wethTokens, { from: owner });
            await vat.frob(ilk, owner, owner, owner, wethTokens, daiDebt, { from: owner });
            await daiJoin.exit(owner, daiTokens, { from: owner });

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
                await wethDealer.debtYDai(maturity1, user2),
                yDaiTokens.toString(),
                'User2 should have ' + yDaiTokens.toString() + ' maturity1 weth debt, instead has ' + (await wethDealer.debtYDai(maturity1, user2)).toString(),
            );
        });

        it("does not allow to redeem YDai if treasury not settled and cashed", async() => {
            await expectRevert(
                dssShutdown.redeem(maturity1, yDaiTokens, user2, { from: user2 }),
                "DssShutdown: Not ready",
            );
        });

        it("does not allow to settle users if treasury not settled and cashed", async() => {
            await expectRevert(
                dssShutdown.settle(WETH, user2, { from: user2 }),
                "DssShutdown: Not ready",
            );
        });

        it("does not allow to profit if treasury not settled and cashed", async() => {
            await expectRevert(
                dssShutdown.profit(owner, { from: user2 }),
                "DssShutdown: Not ready",
            );
        });

        describe("with Dss shutdown initiated and treasury settled", () => {
            beforeEach(async() => {
                await end.cage({ from: owner });
                await end.setTag(ilk, tag, { from: owner });
                await end.setDebt(1, { from: owner });
                await end.setFix(ilk, fix, { from: owner });
                await end.skim(ilk, user1, { from: owner });
                await end.skim(ilk, user2, { from: owner });
                await end.skim(ilk, owner, { from: owner });
                await dssShutdown.settleTreasury({ from: owner });
                await dssShutdown.cashSavings({ from: owner });
            });

            it("does not allow to profit if there is user debt", async() => {
                await expectRevert(
                    dssShutdown.profit(owner, { from: user2 }),
                    "DssShutdown: Redeem all yDai",
                );
            });

            it("user can redeem YDai", async() => {
                await dssShutdown.redeem(maturity1, yDaiTokens, user2, { from: user2 });

                assert.equal(
                    await weth.balanceOf(user2),
                    wethTokens.sub(1).toString(),
                    'User2 should have ' + wethTokens.sub(1).toString() + ' weth wei, instead has ' + (await weth.balanceOf(user2)).toString(),
                );
            });

            it("allows user to settle weth surplus", async() => {
                await dssShutdown.settle(WETH, user1, { from: user1 });

                assert.equal(
                    await weth.balanceOf(user1),
                    wethTokens.toString(),
                    'User1 should have ' + wethTokens.toString() + ' weth wei',
                );
            });

            it("users can be forced to settle weth surplus", async() => {
                await dssShutdown.settle(WETH, user1, { from: owner });

                assert.equal(
                    await weth.balanceOf(user1),
                    wethTokens.toString(),
                    'User1 should have ' + wethTokens.toString() + ' weth wei',
                );
            });

            it("allows user to settle chai surplus", async() => {
                await dssShutdown.settle(CHAI, user1, { from: user1 });

                // Remember that chai is converted to weth when withdrawing
                assert.equal(
                    await weth.balanceOf(user1),
                    wethTokens.sub(1).toString(),
                    'User1 should have ' + wethTokens.sub(1).toString() + ' weth wei',
                );
            });

            it("users can be forced to settle chai surplus", async() => {
                await dssShutdown.settle(CHAI, user1, { from: owner });

                // Remember that chai is converted to weth when withdrawing
                assert.equal(
                    await weth.balanceOf(user1),
                    wethTokens.sub(1).toString(),
                    'User1 should have ' + wethTokens.sub(1).toString() + ' weth wei',
                );
            });

            it("allows user to settle weth debt", async() => {
                await dssShutdown.settle(WETH, user2, { from: user2 });

                assert.equal(
                    await wethDealer.debtYDai(maturity1, user2),
                    0,
                    'User2 should have no maturity1 weth debt',
                );
            });

            it("allows user to settle chai debt", async() => {
                await dssShutdown.settle(CHAI, user2, { from: user2 });

                assert.equal(
                    await chaiDealer.debtYDai(maturity1, user2),
                    0,
                    'User2 should have no maturity1 chai debt',
                );
            });

            it("allows user to settle mutiple weth positions", async() => {
                await dssShutdown.settle(WETH, user3, { from: user3 });

                assert.equal(
                    await weth.balanceOf(user3),
                    wethTokens.add(1).toString(),
                    'User1 should have ' + wethTokens.add(1).toString() + ' weth wei, instead has ' + (await weth.balanceOf(user3)),
                );
            });

            describe("with all yDai redeemed", () => {
                beforeEach(async() => {
                    await dssShutdown.redeem(maturity1, yDaiTokens.mul(2), user2, { from: user2 });
                    await dssShutdown.redeem(maturity1, yDaiTokens, user3, { from: user3 });
                    await dssShutdown.redeem(maturity2, yDaiTokens, user3, { from: user3 });
                });

                it("allows to extract profit", async() => {
                    const profit = await weth.balanceOf(dssShutdown.address);

                    await dssShutdown.profit(owner, { from: owner });
    
                    assert.equal(
                        (await weth.balanceOf(owner)).toString(),
                        profit,
                        'Owner should have ' + profit + ' weth, instead has ' + (await weth.balanceOf(owner)),
                    );
                });
            });
        });
    });
});