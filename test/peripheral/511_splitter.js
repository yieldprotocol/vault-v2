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

// Market
const Market = artifacts.require('Market');

// Peripheral
const EthProxy = artifacts.require('EthProxy');
const Unwind = artifacts.require('Unwind');
const Splitter = artifacts.require('Splitter');

// Mocks
const FlashMinterMock = artifacts.require('FlashMinterMock');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');
const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { assert, expect } = require('chai');

contract('Splitter', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let jug;
    let pot;
    let end;
    let chai;
    let gasToken;
    let treasury;
    let yDai1;
    let yDai2;
    let controller;
    let market1;
    let splitter1;
    let flashMinter;

    let WETH = web3.utils.fromAscii("ETH-A");
    let ilk = web3.utils.fromAscii("ETH-A");
    let Line = web3.utils.fromAscii("Line");
    let spotName = web3.utils.fromAscii("spot");
    let linel = web3.utils.fromAscii("line");

    const limits =  toRad(10000);
    const spot = toRay(1.2);

    const rate1 = toRay(1.4);
    const chi1 = toRay(1.2);
    const rate2 = toRay(1.82);
    const chi2 = toRay(1.5);

    const chiDifferential  = divRay(chi2, chi1);

    const daiDebt1 = toWad(96);
    const daiTokens1 = mulRay(daiDebt1, rate1);
    const yDaiTokens1 = daiTokens1;
    const wethTokens1 = divRay(daiTokens1, spot);
    const chaiTokens1 = divRay(daiTokens1, chi1);

    const daiTokens2 = mulRay(daiTokens1, chiDifferential);
    const wethTokens2 = mulRay(wethTokens1, chiDifferential)

    let maturity1;

    // Scenario in which the user mints daiTokens2 yDai1, chi increases by a 25%, and user redeems daiTokens1 yDai1
    const daiDebt2 = mulRay(daiDebt1, chiDifferential);
    const savings1 = daiTokens2;
    const savings2 = mulRay(savings1, chiDifferential);
    const yDaiSurplus = subBN(daiTokens2, daiTokens1);
    const savingsSurplus = subBN(savings2, daiTokens2);

    // Convert eth to weth and use it to borrow `daiTokens` from MakerDAO
    // This function shadows and uses global variables, careful.
    async function getDai(user, daiTokens_){
        await vat.hope(daiJoin.address, { from: user });
        await vat.hope(wethJoin.address, { from: user });

        const daiDebt_ = divRay(daiTokens_, rate1);
        const wethTokens_ = divRay(daiTokens_, spot);

        await weth.deposit({ from: user, value: wethTokens_ });
        await weth.approve(wethJoin.address, wethTokens_, { from: user });
        await wethJoin.join(user, wethTokens_, { from: user });
        await vat.frob(ilk, user, user, user, wethTokens_, daiDebt_, { from: user });
        await daiJoin.exit(user, daiTokens_, { from: user });
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
        await vat.init(ilk, { from: owner }); // Set ilk rate (stability fee accumulator) to 1.0

        weth = await Weth.new({ from: owner });
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        await vat.file(ilk, spotName, spot, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits);

        // Setup jug
        jug = await Jug.new(vat.address);
        await jug.init(ilk, { from: owner }); // Set ilk duty (stability fee) to 1.0

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
        );

        // Setup Treasury
        treasury = await Treasury.new(
            vat.address,
            weth.address,
            dai.address,
            wethJoin.address,
            daiJoin.address,
            pot.address,
            chai.address,
        );

        // Setup GasToken
        gasToken = await GasToken.new();

        // Setup Controller
        controller = await Controller.new(
            vat.address,
            pot.address,
            treasury.address,
            { from: owner },
        );
        treasury.orchestrate(controller.address, { from: owner });
        
        // Setup yDai1
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952; // One year
        yDai1 = await YDai.new(
            vat.address,
            jug.address,
            pot.address,
            treasury.address,
            maturity1,
            "Name",
            "Symbol"
        );
        await treasury.orchestrate(yDai1.address, { from: owner });
        controller.addSeries(yDai1.address, { from: owner });
        yDai1.orchestrate(controller.address, { from: owner });

        // Setup Market
        market1 = await Market.new(
            dai.address,
            yDai1.address,
            { from: owner }
        );

        // Setup Splitter
        splitter1 = await Splitter.new(
            vat.address,
            weth.address,
            dai.address,
            wethJoin.address,
            daiJoin.address,
            treasury.address,
            yDai1.address,
            controller.address,
            market1.address,
            { from: owner }
        );

        // Test setup
        
        // Increase the rate accumulator
        await vat.fold(ilk, vat.address, subBN(rate1, toRay(1)), { from: owner }); // Fold only the increase from 1.0
        await pot.setChi(chi1, { from: owner }); // Set the savings accumulator

        // Allow owner to mint yDai the sneaky way, without recording a debt in controller
        await yDai1.orchestrate(owner, { from: owner });

        // Initialize Market1
        const daiReserves = daiTokens1.mul(5);
        await getDai(owner, daiReserves)
        await dai.approve(market1.address, daiReserves, { from: owner });
        await market1.init(daiReserves, { from: owner });

        // Add yDai
        const additionalYDaiReserves = yDaiTokens1.mul(2);
        await yDai1.mint(owner, additionalYDaiReserves, { from: owner });
        await yDai1.approve(market1.address, additionalYDaiReserves, { from: owner });
        await market1.sellYDai(owner, owner, additionalYDaiReserves, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("does not allow to move more debt than existing in maker", async() => {
        await expectRevert(
            splitter1.makerToYield(user, wethTokens1, daiTokens1, { from: user }),
            "Splitter: Not enough debt in Maker",
        );
    });

    it("does not allow to move more weth than posted in maker", async() => {
        await getDai(user, daiTokens1);

        await expectRevert(
            splitter1.makerToYield(user, wethTokens1.mul(2), daiTokens1, { from: user }),
            "Splitter: Not enough collateral in Maker",
        );
    });

    it("moves maker vault to yield", async() => {
        // console.log("      Dai: " + daiTokens1.toString());
        // console.log("      Weth: " + wethTokens1.toString());
        await getDai(user, daiTokens1);

        // This lot can be avoided if the user is certain that he has enough Weth in Controller
        // The amount of yDai to be borrowed can be obtained from Market through Splitter
        // As time passes, the amount of yDai required decreases, so this value will always be slightly higher than needed
        const yDaiNeeded = await splitter1.yDaiForDai(daiTokens1);
        // console.log("      YDai: " + yDaiNeeded.toString());

        // Once we know how much yDai debt we will have, we can see how much weth we need to move
        const wethInController = new BN(await splitter1.wethForYDai(yDaiNeeded, { from: user }));

        // If we need any extra, we are posting it directly on Controller
        const extraWethNeeded = wethInController.sub(new BN(wethTokens1.toString())); // It will always be zero or more
        await weth.deposit({ from: user, value: extraWethNeeded });
        await weth.approve(treasury.address, extraWethNeeded, { from: user });
        await controller.post(WETH, user, user, extraWethNeeded, { from: user });
    
        // Add permissions for vault migration
        await controller.addDelegate(splitter1.address, { from: user }); // Allowing Splitter to create debt for use in Yield
        await vat.hope(splitter1.address, { from: user }); // Allowing Splitter to manipulate debt for user in MakerDAO
        // Go!!!
        assert.equal(
            (await vat.urns(WETH, user)).ink,
            wethTokens1.toString(),
        );
        assert.equal(
            (await vat.urns(WETH, user)).art,
            divRay(daiTokens1, rate1).toString(),
        );
        assert.equal(
            (await controller.posted(WETH, user)).toString(),
            extraWethNeeded.toString(),
        );
        assert.equal(
            (await controller.debtYDai(WETH, maturity1, user)).toString(),
            0,
        );
        
        await splitter1.makerToYield(user, wethTokens1, daiTokens1, { from: user });
        
        assert.equal(
            await yDai1.balanceOf(splitter1.address),
            0,
        );
        assert.equal(
            await dai.balanceOf(splitter1.address),
            0,
        );
        assert.equal(
            await weth.balanceOf(splitter1.address),
            0,
        );
        assert.equal(
            (await vat.urns(WETH, user)).ink,
            0,
        );
        assert.equal(
            (await vat.urns(WETH, user)).art,
            0,
        );
        assert.equal(
            (await controller.posted(WETH, user)).toString(),
            wethInController.toString(),
        );
        const yDaiDebt = await controller.debtYDai(WETH, maturity1, user);
        expect(yDaiDebt).to.be.bignumber.lt(yDaiNeeded);
        expect(yDaiDebt).to.be.bignumber.gt(yDaiNeeded.mul(new BN('9999')).div(new BN('10000')));
    });

    it("does not allow to move more debt than existing in yield", async() => {
        await expectRevert(
            splitter1.yieldToMaker(user, yDaiTokens1, wethTokens1, { from: user }),
            "Splitter: Not enough debt in Yield",
        );
    });

    it("does not allow to move more weth than posted in yield", async() => {
        await postWeth(user, wethTokens1);
        await controller.borrow(WETH, maturity1, user, user, yDaiTokens1, { from: user });

        await expectRevert(
            splitter1.yieldToMaker(user, yDaiTokens1, wethTokens1.mul(2), { from: user }),
            "Splitter: Not enough collateral in Yield",
        );
    });

    it("moves yield vault to maker", async() => {
        // console.log("      Dai: " + daiTokens1.toString());
        // console.log("      Weth: " + wethTokens1.toString());
        await postWeth(user, wethTokens1);
        await controller.borrow(WETH, maturity1, user, user, yDaiTokens1, { from: user });
        // console.log("      YDai: " + yDaiTokens1.toString());
        
        // Add permissions for vault migration
        await controller.addDelegate(splitter1.address, { from: user }); // Allowing Splitter to create debt for use in Yield
        await vat.hope(splitter1.address, { from: user }); // Allowing Splitter to manipulate debt for user in MakerDAO
        // Go!!!
        assert.equal(
            (await controller.posted(WETH, user)).toString(),
            wethTokens1.toString(),
        );
        assert.equal(
            (await controller.debtYDai(WETH, maturity1, user)).toString(),
            yDaiTokens1.toString(),
        );
        assert.equal(
            (await vat.urns(WETH, user)).ink,
            0,
        );
        assert.equal(
            (await vat.urns(WETH, user)).art,
            0,
        );

        // Will need this one for testing. As time passes, even for one block, the resulting dai debt will be higher than this value
        const makerDebtEstimate = new BN(await splitter1.daiForYDai(yDaiTokens1));

        await splitter1.yieldToMaker(user, yDaiTokens1, wethTokens1, { from: user });

        assert.equal(
            await yDai1.balanceOf(splitter1.address),
            0,
        );
        assert.equal(
            await dai.balanceOf(splitter1.address),
            0,
        );
        assert.equal(
            await weth.balanceOf(splitter1.address),
            0,
        );
        assert.equal(
            (await controller.posted(WETH, user)).toString(),
            0,
        );
        assert.equal(
            (await controller.debtYDai(WETH, maturity1, user)).toString(),
            0,
        );
        assert.equal(
            (await vat.urns(WETH, user)).ink,
            wethTokens1.toString(),
        );
        const makerDebt = (mulRay(((await vat.urns(WETH, user)).art).toString(), rate1)).toString();
        expect(makerDebt).to.be.bignumber.gt(makerDebtEstimate);
        expect(makerDebt).to.be.bignumber.lt(makerDebtEstimate.mul(new BN('10001')).div(new BN('10000')));
    });
});