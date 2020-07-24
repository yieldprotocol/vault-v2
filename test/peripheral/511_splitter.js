const Market = artifacts.require('Market');
const Splitter = artifacts.require('Splitter');

const { BigNumber } = require("ethers");
const { BN, expectRevert } = require('@openzeppelin/test-helpers');
const { WETH, rate1, daiTokens1, wethTokens1, addBN, mulRay, divRay } = require('../shared/utils');
const { YieldEnvironmentLite } = require("../shared/fixtures");
const { assert, expect } = require('chai');

contract('Splitter', async (accounts) =>  {
    let [ owner, user ] = accounts;

    const yDaiTokens1 = daiTokens1;
    let maturity1;

    beforeEach(async() => {
        yield = await YieldEnvironmentLite.setup();
        maker = yield.maker;
        controller = yield.controller;
        treasury = yield.treasury;
        vat = yield.maker.vat;
        dai = yield.maker.dai;
        weth = yield.maker.weth;
        wethJoin = yield.maker.wethJoin;
        daiJoin = yield.maker.daiJoin;

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 30000000; // Far enough so that the extra weth to borrow is above dust
        yDai1 = await yield.newYDai(maturity1, "Name", "Symbol");

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

        // Allow owner to mint yDai the sneaky way, without recording a debt in controller
        await yDai1.orchestrate(owner, { from: owner });

        // Initialize Market1
        const daiReserves = daiTokens1.mul(5);
        await yield.maker.getDai(owner, daiReserves, rate1);
        await dai.approve(market1.address, daiReserves, { from: owner });
        await market1.init(daiReserves, { from: owner });

        // Add yDai
        const additionalYDaiReserves = yDaiTokens1.mul(2);
        await yDai1.mint(owner, additionalYDaiReserves, { from: owner });
        await yDai1.approve(market1.address, additionalYDaiReserves, { from: owner });
        await market1.sellYDai(owner, owner, additionalYDaiReserves, { from: owner });
    });

    it("does not allow to move more debt than existing in maker", async() => {
        await expectRevert(
            splitter1.makerToYield(user, wethTokens1, daiTokens1.mul(10), { from: user }),
            "Splitter: Not enough debt in Maker",
        );
    });

    it("does not allow to move more weth than posted in maker", async() => {
        await yield.maker.getDai(user, daiTokens1, rate1);

        await expectRevert(
            splitter1.makerToYield(user, BigNumber.from(wethTokens1).mul(10), daiTokens1, { from: user }),
            "Splitter: Not enough collateral in Maker",
        );
    });

    it("moves maker vault to yield", async() => {
        // console.log("      Dai: " + daiTokens1.toString());
        // console.log("      Weth: " + wethTokens1.toString());
        await yield.maker.getDai(user, daiTokens1, rate1);

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
            BigNumber.from(wethTokens1).mul(2).toString(), // `getDai` puts in vat twice as much weth as needed to borrow the dai
        );
        assert.equal(
            (await vat.urns(WETH, user)).art,
            addBN(divRay(daiTokens1, rate1), 1).toString(), // TODO: Check rounding in `getDai` and Splitter:175
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
            wethTokens1.toString(),
        );
        assert.equal(
            (await vat.urns(WETH, user)).art,
            1,
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
        await yield.postWeth(user, wethTokens1);
        await controller.borrow(WETH, maturity1, user, user, yDaiTokens1, { from: user });

        await expectRevert(
            splitter1.yieldToMaker(user, yDaiTokens1, BigNumber.from(wethTokens1).mul(2), { from: user }),
            "Splitter: Not enough collateral in Yield",
        );
    });

    it("moves yield vault to maker", async() => {
        // console.log("      Dai: " + daiTokens1.toString());
        // console.log("      Weth: " + wethTokens1.toString());
        await yield.postWeth(user, wethTokens1);
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
