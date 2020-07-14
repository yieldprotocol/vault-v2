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
const GasToken = artifacts.require('GasToken1');

// Common
const Treasury = artifacts.require('Treasury');

// YDai
const YDai = artifacts.require('YDai');
const Controller = artifacts.require('Controller');

// Peripheral
const EthProxy = artifacts.require('EthProxy');
const Unwind = artifacts.require('Unwind');

const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('Controller - Gas Tokens', async (accounts) =>  {
    let [ owner, user1, user2 ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let jug;
    let pot;
    let chai;
    let gasToken;
    let treasury;
    let yDai1;
    let yDai2;
    let controller;

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
    const chi  = toRay(1.25);
    const daiDebt = toWad(120);
    const daiTokens = mulRay(daiDebt, rate);
    const wethTokens = divRay(daiTokens, spot);
    let maturity1;
    let maturity2;

    const gasTokens = 10;

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

    // Convert eth to weth and post it to yDai
    // This function shadows and uses global variables, careful.
    async function postWeth(user, wethTokens){
        await weth.deposit({ from: user, value: wethTokens });
        await weth.approve(treasury.address, wethTokens, { from: user });
        await controller.post(WETH, user, user, wethTokens, { from: user });
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

        // Setup GasToken
        gasToken = await GasToken.new();

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
            weth.address,
            dai.address,
            pot.address,
            chai.address,
            gasToken.address,
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
        await pot.setChi(chi, { from: owner });
        await vat.fold(WETH, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0
        await getDai(user1, daiTokens.mul(2));
        await getDai(user2, daiTokens);
        await postWeth(user1, wethTokens.mul(2));
        await postWeth(user2, wethTokens);
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });
    
    /* it("get the size of the contract", async() => {
        console.log();
        console.log("·--------------------|------------------|------------------|------------------·");
        console.log("|  Contract          ·  Bytecode        ·  Deployed        ·  Constructor     |");
        console.log("·····················|··················|··················|···················");
        
        const bytecode = controller.constructor._json.bytecode;
        const deployed = controller.constructor._json.deployedBytecode;
        const sizeOfB  = bytecode.length / 2;
        const sizeOfD  = deployed.length / 2;
        const sizeOfC  = sizeOfB - sizeOfD;
        console.log(
            "|  " + (controller.constructor._json.contractName).padEnd(18, ' ') +
            "|" + ("" + sizeOfB).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfD).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfC).padStart(16, ' ') + "  |");
        console.log("·--------------------|------------------|------------------|------------------·");
        console.log();
    }); */

    it("mints gas tokens when borrowing", async() => {
        await dai.approve(treasury.address, daiTokens, { from: user1 });
        await controller.borrow(WETH, maturity1, user1, user1, daiTokens, { from: user1 });

        assert.equal(
            await gasToken.balanceOf(controller.address),
            gasTokens,
            "Controller should have gasTokens",
        );
    });

    it("takes gas tokens when a new user1 posts for the first time, if available", async() => {
        await gasToken.mint(gasTokens, { from: user1 });
        assert.equal(
            await gasToken.balanceOf(user1),
            gasTokens,
            "User should have gasTokens",
        );
        await gasToken.approve(controller.address, gasTokens, { from: user1 });

        await dai.approve(treasury.address, daiTokens, { from: user1 });
        await controller.borrow(WETH, maturity1, user1, user1, daiTokens, { from: user1 });

        assert.equal(
            await gasToken.balanceOf(user1),
            0,
            "User should have no gasTokens",
        );
        assert.equal(
            await gasToken.balanceOf(controller.address),
            gasTokens,
            "Controller should have gasTokens",
        );
    });

    it("does not transfer gas tokens if borrowing amount and debt are zero", async() => {
        await controller.borrow(WETH, maturity1, user1, user1, 0, { from: user1 });

        assert.equal(
            await gasToken.balanceOf(user1),
            0,
            "User should not have gasTokens",
        );
    });

    describe("with debt", () => {
        beforeEach(async() => {
            await dai.approve(treasury.address, daiTokens, { from: user1 });
            await controller.borrow(WETH, maturity1, user1, user1, daiTokens, { from: user1 });

            assert.equal(
                await gasToken.balanceOf(controller.address),
                gasTokens,
                "Controller should have gasTokens",
            );
        });

        it("mints gas tokens when a new user borrows for the first time", async() => {
            await dai.approve(treasury.address, daiTokens, { from: user2 });
            await controller.borrow(WETH, maturity1, user2, user2, daiTokens, { from: user2 });
    
            assert.equal(
                await gasToken.balanceOf(controller.address),
                gasTokens * 2,
                "Controller should have more gasTokens",
            );
        });

        it("does not mint more gas tokens when same user borrows again", async() => {
            await dai.approve(treasury.address, daiTokens, { from: user1 });
            await controller.borrow(WETH, maturity1, user1, user1, daiTokens, { from: user1 });
    
            assert.equal(
                await gasToken.balanceOf(controller.address),
                gasTokens.toString(),
                "Controller should have gasTokens",
            );
        });

        it("does not transfer gas tokens on partial repayments", async() => {
            await controller.repayYDai(WETH, maturity1, user1, user1, daiTokens.sub(1), { from: user1 });

            assert.equal(
                await gasToken.balanceOf(user1),
                0,
                "User should not have gasTokens",
            );
        });

        it("transfers gas tokens on repayment of all debt", async() => {
            await controller.repayYDai(WETH, maturity1, user1, user1, daiTokens, { from: user1 });

            assert.equal(
                await gasToken.balanceOf(user1),
                gasTokens.toString(),
                "User should have gasTokens",
            );
        });

        // TODO: Test gas tokens for `grab`
    });
});