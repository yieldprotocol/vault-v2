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

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');
const { expectRevert, expectEvent } = require('@openzeppelin/test-helpers');

contract('yDai - Delegable', async (accounts) =>  {
    let [ owner, holder, other ] = accounts;
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
    
    let maturity;
    let WETH = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")

    const limits =  toRad(10000);
    const spot = toRay(1.5);
    const rate1 = toRay(1.2);
    const chi1 = toRay(1.3);
    const rate2 = toRay(1.5);
    const chi2 = toRay(1.82);

    const chiDifferential  = divRay(chi2, chi1); // 1.82 / 1.3 = 1.4

    const daiDebt1 = toWad(96);
    const daiTokens1 = mulRay(daiDebt1, rate1);
    const wethTokens1 = divRay(daiTokens1, spot);

    const daiTokens2 = mulRay(daiTokens1, chiDifferential);
    const wethTokens2 = mulRay(wethTokens1, chiDifferential)

    // Scenario in which the user mints daiTokens2 yDai, chi increases by a 25%, and user redeems daiTokens1 yDai
    const daiDebt2 = mulRay(daiDebt1, chiDifferential);
    const savings1 = daiTokens2;
    const savings2 = mulRay(savings1, chiDifferential);
    const yDaiSurplus = subBN(daiTokens2, daiTokens1);
    const savingsSurplus = subBN(savings2, daiTokens2);

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
        await pot.setChi(chi1, { from: owner });
        await vat.fold(WETH, vat.address, subBN(rate1, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        // Post collateral to MakerDAO through Treasury
        await treasury.orchestrate(owner, { from: owner });
        await weth.deposit({ from: owner, value: wethTokens1 });
        await weth.approve(treasury.address, wethTokens1, { from: owner });
        await treasury.pushWeth(owner, wethTokens1, { from: owner });
        assert.equal(
            (await vat.urns(WETH, treasury.address)).ink,
            wethTokens1.toString(),
        );

        // Mint some yDai the sneaky way
        await yDai1.orchestrate(owner, { from: owner });
        await yDai1.mint(holder, daiTokens1, { from: owner });

        // yDai matures
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai1.mature();

        assert.equal(
            await yDai1.balanceOf(holder),
            daiTokens1.toString(),
            "Holder does not have yDai",
        );
        assert.equal(
            await treasury.savings.call(),
            0,
            "Treasury has no savings",
        );
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("redeem is allowed for account holder", async() => {
        await yDai1.approve(yDai1.address, daiTokens1, { from: holder });
        await yDai1.redeem(holder, holder, daiTokens1, { from: holder });

        assert.equal(
            await treasury.debt(),
            daiTokens1.toString(),
            "Treasury should have debt",
        );
        assert.equal(
            await dai.balanceOf(holder),
            daiTokens1.toString(),
            "Holder should have dai",
        );
    });

    it("redeem is not allowed for non designated accounts", async() => {
        await yDai1.approve(yDai1.address, daiTokens1, { from: holder });
        await expectRevert(
            yDai1.redeem(holder, holder, daiTokens1, { from: other }),
            "YDai: Only Holder Or Delegate",
        );
    });

    it("redeem is allowed for delegates", async() => {
        await yDai1.approve(yDai1.address, daiTokens1, { from: holder });
        expectEvent(
            await yDai1.addDelegate(other, { from: holder }),
            "Delegate",
            {
                user: holder,
                delegate: other,
                enabled: true,
            },
        );
        await yDai1.redeem(holder, holder, daiTokens1, { from: other });

        assert.equal(
            await treasury.debt(),
            daiTokens1.toString(),
            "Treasury should have debt",
        );
        assert.equal(
            await dai.balanceOf(holder),
            daiTokens1.toString(),
            "Holder should have dai",
        );
    });

    describe("with delegates", async() => {
        beforeEach(async() => {
            await yDai1.addDelegate(other, { from: holder });
        });

        it("redeem is not allowed if delegation revoked", async() => {
            expectEvent(
                await yDai1.revokeDelegate(other, { from: holder }),
                "Delegate",
                {
                    user: holder,
                    delegate: other,
                    enabled: false,
                },
            );

            await expectRevert(
                yDai1.redeem(holder, holder, daiTokens1, { from: other }),
                "YDai: Only Holder Or Delegate",
            );
        });
    });
});