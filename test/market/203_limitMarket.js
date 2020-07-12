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

// Market
const Market = artifacts.require('Market');
const LimitMarket = artifacts.require('LimitMarket');

// Mocks
const FlashMinterMock = artifacts.require('FlashMinterMock');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');
const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { assert, expect } = require('chai');

contract('LimitMarket', async (accounts) =>  {
    let [ owner, user1, operator, from, to ] = accounts;
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
    let splitter;
    let market;
    let limitMarket;
    let flashMinter;

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

    let maturity;

    // Scenario in which the user mints daiTokens2 yDai1, chi increases by a 25%, and user redeems daiTokens1 yDai1
    const daiDebt2 = mulRay(daiDebt1, chiDifferential);
    const savings1 = daiTokens2;
    const savings2 = mulRay(savings1, chiDifferential);
    const yDaiSurplus = subBN(daiTokens2, daiTokens1);
    const savingsSurplus = subBN(savings2, daiTokens2);

    // Convert eth to weth and use it to borrow `daiTokens` from MakerDAO
    // This function shadows and uses global variables, careful.
    async function getDai(user, daiTokens){
        await vat.hope(daiJoin.address, { from: user });
        await vat.hope(wethJoin.address, { from: user });

        const daiDebt = divRay(daiTokens, rate1);
        const wethTokens = divRay(daiTokens, spot);

        await weth.deposit({ from: user, value: wethTokens });
        await weth.approve(wethJoin.address, wethTokens, { from: user });
        await wethJoin.join(user, wethTokens, { from: user });
        await vat.frob(ilk, user, user, user, wethTokens, daiDebt, { from: user });
        await daiJoin.exit(user, daiTokens, { from: user });
    }

    // From eth, borrow `daiTokens` from MakerDAO and convert them to chai
    // This function shadows and uses global variables, careful.
    async function getChai(user, chaiTokens){
        const daiTokens = mulRay(chaiTokens, chi1);
        await getDai(user, daiTokens);
        await dai.approve(chai.address, daiTokens, { from: user });
        await chai.join(user, daiTokens, { from: user });
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

        treasury = await Treasury.new(
            vat.address,
            weth.address,
            dai.address,
            wethJoin.address,
            daiJoin.address,
            pot.address,
            chai.address,
        );
    
        // Setup yDai1
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 31556952; // One year
        yDai1 = await YDai.new(
            vat.address,
            jug.address,
            pot.address,
            treasury.address,
            maturity,
            "Name",
            "Symbol"
        );
        await treasury.orchestrate(yDai1.address, { from: owner });

        // Setup Market
        market = await Market.new(
            pot.address,
            chai.address,
            yDai1.address,
            { from: owner }
        );

        // Setup LimitMarket
        limitMarket = await LimitMarket.new(
            chai.address,
            yDai1.address,
            market.address,
            { from: owner }
        );

        // Test setup
        
        // Increase the rate accumulator
        await vat.fold(ilk, vat.address, subBN(rate1, toRay(1)), { from: owner }); // Fold only the increase from 1.0
        await pot.setChi(chi1, { from: owner }); // Set the savings accumulator

        // Allow owner to mint yDai the sneaky way, without recording a debt in controller
        await yDai1.orchestrate(owner, { from: owner });

    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    describe("with liquidity", () => {
        beforeEach(async() => {
            await getChai(user1, chaiTokens1)
            await yDai1.mint(user1, yDaiTokens1, { from: owner });
    
            await chai.approve(market.address, chaiTokens1, { from: user1 });
            await yDai1.approve(market.address, yDaiTokens1, { from: user1 });
            await market.init(chaiTokens1, yDaiTokens1, { from: user1 });
        });

        it("mints liquidity tokens", async() => {
            await getChai(user1, chaiTokens1)
            await yDai1.mint(user1, yDaiTokens1, { from: owner });

            await chai.approve(market.address, chaiTokens1, { from: user1 });
            await yDai1.approve(market.address, yDaiTokens1, { from: user1 });
            await market.mint(chaiTokens1, { from: user1 });

            assert.equal(
                await market.balanceOf(user1),
                2000,
                "User1 should have 2000 liquidity tokens",
            );
        });

        it("burns liquidity tokens", async() => {
            await market.approve(market.address, 500, { from: user1 });
            await market.burn(500, { from: user1 });

            assert.equal(
                await chai.balanceOf(user1),
                chaiTokens1.div(2).toString(),
                "User1 should have chai tokens",
            );
            assert.equal(
                await yDai1.balanceOf(user1),
                yDaiTokens1.div(2).toString(),
                "User1 should have yDai tokens",
            );
        });

        it("sells chai", async() => {
            const oneToken = toWad(1);
            await getChai(from, chaiTokens1);

            await market.addDelegate(limitMarket.address, { from: from });
            await chai.approve(market.address, oneToken, { from: from });
            await limitMarket.sellChai(from, to, oneToken, oneToken.div(2), { from: from });

            assert.equal(
                await chai.balanceOf(from),
                chaiTokens1.sub(oneToken).toString(),
                "'From' wallet should have " + chaiTokens1.sub(oneToken) + " chai tokens",
            );

            const expectedYDaiOut = (new BN(oneToken.toString())).mul(new BN('1436')).div(new BN('1000')); // I just hate javascript
            const yDaiOut = new BN(await yDai1.balanceOf(to));
            expect(yDaiOut).to.be.bignumber.gt(expectedYDaiOut.mul(new BN('99')).div(new BN('100')));
            expect(yDaiOut).to.be.bignumber.lt(expectedYDaiOut.mul(new BN('101')).div(new BN('100')));
        });

        it("doesn't sell chai if limit not reached", async() => {
            const oneToken = toWad(1);
            await getChai(from, chaiTokens1);

            await market.addDelegate(limitMarket.address, { from: from });
            await chai.approve(market.address, oneToken, { from: from });

            await expectRevert(
                limitMarket.sellChai(from, to, oneToken, oneToken.mul(2), { from: from }),
                "LimitMarket: Limit not reached",
            );
        });

        it("buys chai", async() => {
            const oneToken = toWad(1);
            await yDai1.mint(from, yDaiTokens1, { from: owner });

            await market.addDelegate(limitMarket.address, { from: from });
            await yDai1.approve(market.address, yDaiTokens1, { from: from });
            await limitMarket.buyChai(from, to, oneToken, oneToken.mul(2), { from: from });

            const expectedYDaiIn = (new BN(oneToken.toString())).mul(new BN('14435')).div(new BN('10000')); // I just hate javascript
            const yDaiIn = (new BN(yDaiTokens1.toString())).sub(new BN(await yDai1.balanceOf(from)));
            expect(yDaiIn).to.be.bignumber.gt(expectedYDaiIn.mul(new BN('99')).div(new BN('100')));
            expect(yDaiIn).to.be.bignumber.lt(expectedYDaiIn.mul(new BN('101')).div(new BN('100')));
        });

        it("doesn't buy chai if limit exceeded", async() => {
            const oneToken = toWad(1);
            await yDai1.mint(from, yDaiTokens1, { from: owner });

            await market.addDelegate(limitMarket.address, { from: from });
            await yDai1.approve(market.address, yDaiTokens1, { from: from });

            await expectRevert(
                limitMarket.buyChai(from, to, oneToken, oneToken.div(2), { from: from }),
                "LimitMarket: Limit exceeded",
            );
        });

        it("sells yDai", async() => {
            const oneToken = toWad(1);
            await yDai1.mint(from, oneToken, { from: owner });

            await market.addDelegate(limitMarket.address, { from: from });
            await yDai1.approve(market.address, oneToken, { from: from });
            await limitMarket.sellYDai(from, to, oneToken, oneToken.div(2), { from: from });

            assert.equal(
                await yDai1.balanceOf(from),
                0,
                "'From' wallet should have no yDai tokens",
            );

            const expectedChaiOut = (new BN(oneToken.toString())).mul(new BN('6933')).div(new BN('10000')); // I just hate javascript
            const chaiOut = new BN(await chai.balanceOf(to));
            expect(chaiOut).to.be.bignumber.gt(expectedChaiOut.mul(new BN('99')).div(new BN('100')));
            expect(chaiOut).to.be.bignumber.lt(expectedChaiOut.mul(new BN('101')).div(new BN('100')));
        });

        it("doesn't sell yDai if limit not reached", async() => {
            const oneToken = toWad(1);
            await yDai1.mint(from, oneToken, { from: owner });

            await market.addDelegate(limitMarket.address, { from: from });
            await yDai1.approve(market.address, oneToken, { from: from });

            await expectRevert(
                limitMarket.sellYDai(from, to, oneToken, oneToken.mul(2), { from: from }),
                "LimitMarket: Limit not reached",
            );
        });

        it("buys yDai", async() => {
            const oneToken = toWad(1);
            await getChai(from, chaiTokens1);

            await market.addDelegate(limitMarket.address, { from: from });
            await chai.approve(market.address, chaiTokens1, { from: from });
            await limitMarket.buyYDai(from, to, oneToken, oneToken.mul(2), { from: from });

            assert.equal(
                await yDai1.balanceOf(to),
                oneToken.toString(),
                "'To' wallet should have 1 yDai token",
            );

            const expectedChaiIn = (new BN(oneToken.toString())).mul(new BN('6933')).div(new BN('10000')); // I just hate javascript
            const chaiIn = (new BN(chaiTokens1.toString())).sub(new BN(await chai.balanceOf(from)));
            expect(chaiIn).to.be.bignumber.gt(expectedChaiIn.mul(new BN('99')).div(new BN('100')));
            expect(chaiIn).to.be.bignumber.lt(expectedChaiIn.mul(new BN('101')).div(new BN('100')));
        });

        it("doesn't buy yDai if limit exceeded", async() => {
            const oneToken = toWad(1);
            await getChai(from, chaiTokens1);

            await market.addDelegate(limitMarket.address, { from: from });
            await chai.approve(market.address, chaiTokens1, { from: from });

            await expectRevert(
                limitMarket.buyYDai(from, to, oneToken, oneToken.div(2), { from: from }),
                "LimitMarket: Limit exceeded",
            );
        });
    });
});