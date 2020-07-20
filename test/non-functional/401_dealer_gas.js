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
const Liquidations = artifacts.require('Liquidations');
const Unwind = artifacts.require('Unwind');

const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');

contract('Gas Usage', async (accounts) =>  {
    let [ owner, user1, user2, user3, user4 ] = accounts;
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
    let ethProxy;
    let liquidations;
    let unwind;

    let WETH = web3.utils.fromAscii("ETH-A");
    let CHAI = web3.utils.fromAscii("CHAI");
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
    let maturities;
    let series;

    const tag  = divRay(toRay(1.0), spot); // Irrelevant to the final users
    const fix  = divRay(toRay(1.0), mulRay(spot, toRay(1.1)));
    const fixedWeth = mulRay(daiTokens, fix);

    // Convert eth to weth and use it to borrow `daiTokens` from MakerDAO
    // This function shadows and uses global variables, careful.
    async function getDai(user, daiTokens){
        await vat.hope(daiJoin.address, { from: user });
        await vat.hope(wethJoin.address, { from: user });

        const daiDebt = divRay(daiTokens, rate);
        const wethTokens = divRay(daiTokens, spot);

        await weth.deposit({ from: user, value: wethTokens });
        await weth.approve(wethJoin.address, wethTokens, { from: user });
        await wethJoin.join(user, wethTokens, { from: user });
        await vat.frob(WETH, user, user, user, wethTokens, daiDebt, { from: user });
        await daiJoin.exit(user, daiTokens, { from: user });
    }

    // From eth, borrow `daiTokens` from MakerDAO and convert them to chai
    // This function shadows and uses global variables, careful.
    async function getChai(user, chaiTokens){
        const daiTokens = mulRay(chaiTokens, chi);
        await getDai(user, daiTokens);
        await dai.approve(chai.address, daiTokens, { from: user });
        await chai.join(user, daiTokens, { from: user });
    }

    // Convert eth to weth and post it to yDai
    // This function shadows and uses global variables, careful.
    async function postWeth(user, wethTokens){
        await weth.deposit({ from: user, value: wethTokens });
        await weth.approve(treasury.address, wethTokens, { from: user });
        await controller.post(WETH, user, user, wethTokens, { from: user });
    }

    // Convert eth to chai and post it to yDai
    // This function shadows and uses global variables, careful.
    async function postChai(user, chaiTokens){
        await getChai(user, chaiTokens);
        await chai.approve(treasury.address, chaiTokens, { from: user });
        await controller.post(CHAI, user, user, chaiTokens, { from: user });
    }

    // Add a new yDai series
    // This function uses global variables, careful.
    async function addYDai(maturity){
        yDai = await YDai.new(
            vat.address,
            jug.address,
            pot.address,
            treasury.address,
            maturity,
            "Name",
            "Symbol",
            { from: owner },
        );
        await controller.addSeries(yDai.address, { from: owner });
        await yDai.orchestrate(controller.address, { from: owner });
        await treasury.orchestrate(yDai.address, { from: owner });
        await yDai.orchestrate(unwind.address, { from: owner });
        return yDai;
    }

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

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

        // Setup end
        end = await End.new({ from: owner });
        await end.file(web3.utils.fromAscii("vat"), vat.address);

        // Permissions
        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.rely(jug.address, { from: owner });
        await vat.rely(pot.address, { from: owner });
        await vat.rely(end.address, { from: owner });
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
        await controller.addSeries(yDai1.address, { from: owner });
        await yDai1.orchestrate(controller.address, { from: owner });
        await treasury.orchestrate(yDai1.address, { from: owner });

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
        await controller.addSeries(yDai2.address, { from: owner });
        await yDai2.orchestrate(controller.address, { from: owner });
        await treasury.orchestrate(yDai2.address, { from: owner });

        // Setup Liquidations
        liquidations = await Liquidations.new(
            dai.address,
            treasury.address,
            controller.address,
            { from: owner },
        );
        await controller.orchestrate(liquidations.address, { from: owner });
        await treasury.orchestrate(liquidations.address, { from: owner });

        // Setup EthProxy
        ethProxy = await EthProxy.new(
            weth.address,
            treasury.address,
            controller.address,
            { from: owner },
        );
        
        // Setup Liquidations
        liquidations = await Liquidations.new(
            dai.address,
            treasury.address,
            controller.address,
            { from: owner },
        );
        await controller.orchestrate(liquidations.address, { from: owner });
        await treasury.orchestrate(liquidations.address, { from: owner });

        // Setup Unwind
        unwind = await Unwind.new(
            vat.address,
            daiJoin.address,
            weth.address,
            wethJoin.address,
            jug.address,
            pot.address,
            end.address,
            chai.address,
            treasury.address,
            controller.address,
            liquidations.address,
            { from: owner },
        );
        await controller.orchestrate(unwind.address, { from: owner });
        await treasury.orchestrate(unwind.address, { from: owner });
        await treasury.registerUnwind(unwind.address, { from: owner });
        await yDai1.orchestrate(unwind.address, { from: owner });
        await yDai2.orchestrate(unwind.address, { from: owner });
        await liquidations.orchestrate(unwind.address, { from: owner });

        // Tests setup
        await pot.setChi(chi, { from: owner });
        await vat.fold(WETH, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });
        await treasury.orchestrate(owner, { from: owner });
        await end.rely(owner, { from: owner });       // `owner` replaces MKR governance
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
                series.push(await addYDai(maturity));
            }
        });

        describe("post and borrow", () => {
            beforeEach(async() => {
                // Set the scenario
                
                for (let i = 0; i < maturities.length; i++) {
                    await postWeth(user3, wethTokens);
                    await controller.borrow(WETH, maturities[i], user3, user3, daiTokens, { from: user3 });
                }
            });

            it("borrow a second time (no gas bond)", async() => {
                for (let i = 0; i < maturities.length; i++) {
                    await postWeth(user3, wethTokens);
                    await controller.borrow(WETH, maturities[i], user3, user3, daiTokens, { from: user3 });
                }
            });

            it("repayYDai", async() => {
                for (let i = 0; i < maturities.length; i++) {
                    await series[i].approve(treasury.address, daiTokens, { from: user3 });
                    await controller.repayYDai(WETH, maturities[i], user3, user3, daiTokens, { from: user3 });
                }
            });

            it("repayYDai and retrieve gas bond", async() => {
                for (let i = 0; i < maturities.length; i++) {
                    await series[i].approve(controller.address, daiTokens.mul(2), { from: user3 });
                    await controller.repayYDai(WETH, maturities[i], user3, user3, daiTokens.mul(2), { from: user3 });
                }
            });

            it("repayDai and withdraw", async() => {
                await helper.advanceTime(m * 1000);
                await helper.advanceBlock();
                
                for (let i = 0; i < maturities.length; i++) {
                    await getDai(user3, daiTokens);
                    await dai.approve(treasury.address, daiTokens, { from: user3 });
                    await controller.repayDai(WETH, maturities[i], user3, user3, daiTokens, { from: user3 });
                }
                
                for (let i = 0; i < maturities.length; i++) {
                    await controller.withdraw(WETH, user3, user3, wethTokens, { from: user3 });
                }
            });

            describe("during dss unwind", () => {
                beforeEach(async() => {
                    // Unwind
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