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

// Mocks
const FlashMinterMock = artifacts.require('FlashMinterMock');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');
const { expectEvent, expectRevert } = require('@openzeppelin/test-helpers');

contract('yDai', async (accounts) =>  {
    let [ owner, user1, other ] = accounts;
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
    let flashMinter;

    let WETH = web3.utils.fromAscii("ETH-A");
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
    const wethTokens1 = divRay(daiTokens1, spot);

    const daiTokens2 = mulRay(daiTokens1, chiDifferential);
    const wethTokens2 = mulRay(wethTokens1, chiDifferential)

    let maturity;

    // Scenario in which the user mints daiTokens2 yDai1, chi increases by a 25%, and user redeems daiTokens1 yDai1
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
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
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

        // Test setup
        // Setup Flash Minter
        flashMinter = await FlashMinterMock.new(
            { from: owner },
        );
        
        // Increase the rate accumulator
        await vat.fold(WETH, vat.address, subBN(rate1, toRay(1)), { from: owner }); // Fold only the increase from 1.0
        await pot.setChi(chi1, { from: owner }); // Set the savings accumulator

        // Deposit some weth to treasury so that redeem can pull some dai
        await treasury.orchestrate(owner, { from: owner });
        await weth.deposit({ from: owner, value: wethTokens2 });
        await weth.approve(treasury.address, wethTokens2, { from: owner });
        await treasury.pushWeth(owner, wethTokens2, { from: owner });

        // Mint some yDai1 the sneaky way, only difference is that the Controller doesn't record the user debt.
        await yDai1.orchestrate(owner, { from: owner });
        await yDai1.mint(user1, daiTokens1, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("should setup yDai1", async() => {
        assert(
            await yDai1.chiGrowth.call(),
            toRay(1.0).toString(),
            "chi not initialized",
        );
        assert(
            await yDai1.rateGrowth(),
            toRay(1.0).toString(),
            "rate not initialized",
        );
        assert(
            await yDai1.maturity(),
            maturity.toString(),
            "maturity not initialized",
        );
    });

    it("yDai1 is not mature before maturity", async() => {
        assert.equal(
            await yDai1.isMature(),
            false,
        );
    });

    it("yDai1 can't be redeemed before maturity time", async() => {
        await expectRevert(
            yDai1.redeem(user1, user1, daiTokens1, { from: user1 }),
            "YDai: yDai is not mature",
        );
    });

    it("yDai1 cannot mature before maturity time", async() => {
        await expectRevert(
            yDai1.mature(),
            "YDai: Too early to mature",
        );
    });

    it("yDai1 can mature at maturity time", async() => {
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai1.mature();
        assert.equal(
            await yDai1.isMature(),
            true,
        );
    });

    it("yDai flash mints", async() => {
        expectEvent(
            await flashMinter.flashMint(yDai1.address, daiTokens1, web3.utils.fromAscii("DATA"), { from: user1 }),
            "Parameters",
            {
                user: flashMinter.address,
                amount: daiTokens1.toString(),
                data: web3.utils.fromAscii("DATA"),
            },
        );

        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai1.mature();

        await yDai1.redeem(user1, user1, daiTokens1, { from: user1 });

        assert.equal(
            await flashMinter.flashBalance(),
            daiTokens1.toString(),
            "FlashMinter should have seen the tokens",
        );
        assert.equal(
            await yDai1.totalSupply(),
            0,
            "There should be no yDai supply",
        );
    });

    describe("once mature", () => {
        beforeEach(async() => {
            await helper.advanceTime(1000);
            await helper.advanceBlock();
            await yDai1.mature();
        });

        it("yDai1 can't mature more than once", async() => {
            await expectRevert(
                yDai1.mature(),
                "YDai: Already mature",
            );
        });

        it("yDai1 chi gets fixed at maturity time", async() => {
            await pot.setChi(chi2, { from: owner });
            
            assert(
                await yDai1.chiGrowth.call(),
                subBN(chi2, chi1).toString(),
                "Chi differential should be " + subBN(chi2, chi1),
            );
        });

        it("yDai1 rate gets fixed at maturity time", async() => {
            await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner });
            
            assert(
                await yDai1.rateGrowth(),
                subBN(rate2, rate1).toString(),
                "Rate differential should be " + subBN(rate2, rate1),
            );
        });

        it("chiGrowth always <= rateGrowth", async() => {
            await pot.setChi(chi2, { from: owner });

            assert(
                await yDai1.chiGrowth.call(),
                await yDai1.rateGrowth(),
                "Chi differential should be " + await yDai1.rateGrowth(),
            );
        });

        it("redeem burns yDai1 to return dai, pulls dai from Treasury", async() => {
            assert.equal(
                await yDai1.balanceOf(user1),
                daiTokens1.toString(),
                "User1 does not have yDai1",
            );
            assert.equal(
                await dai.balanceOf(user1),
                0,
                "User1 has dai",
            );
    
            await yDai1.approve(yDai1.address, daiTokens1, { from: user1 });
            await yDai1.redeem(user1, user1, daiTokens1, { from: user1 });
    
            assert.equal(
                await dai.balanceOf(user1),
                daiTokens1.toString(),
                "User1 should have dai",
            );
            assert.equal(
                await yDai1.balanceOf(user1),
                0,
                "User1 should not have yDai1",
            );
        });

        it("yDai can be redeemed in favour of others", async() => {
            assert.equal(
                await yDai1.balanceOf(user1),
                daiTokens1.toString(),
                "User1 does not have yDai1",
            );
            assert.equal(
                await dai.balanceOf(other),
                0,
                "Other has dai",
            );
    
            await yDai1.approve(yDai1.address, daiTokens1, { from: user1 });
            await yDai1.redeem(user1, other, daiTokens1, { from: user1 });
    
            assert.equal(
                await dai.balanceOf(other),
                daiTokens1.toString(),
                "Other should have dai",
            );
            assert.equal(
                await yDai1.balanceOf(user1),
                0,
                "User1 should not have yDai1",
            );
        });

        describe("once chi increases", () => {
            beforeEach(async() => {
                await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner }); // Keeping above chi
                await pot.setChi(chi2, { from: owner });

                assert(
                    await yDai1.chiGrowth.call(),
                    chiDifferential.toString(),
                    "chi differential should be " + chiDifferential + ", instead is " + (await yDai1.chiGrowth.call()),
                );
            });
    
            it("redeem with increased chi returns more dai", async() => {
                // Redeem `daiTokens1` yDai to obtain `daiTokens1` * `chiDifferential`

                await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner }); // Keeping above chi
                await pot.setChi(chi2, { from: owner });

                assert.equal(
                    await yDai1.balanceOf(user1),
                    daiTokens1.toString(),
                    "User1 does not have yDai1",
                );
        
                await yDai1.approve(yDai1.address, daiTokens1, { from: user1 });
                await yDai1.redeem(user1, user1, daiTokens1, { from: user1 });
        
                assert.equal(
                    await dai.balanceOf(user1),
                    daiTokens2.toString(),
                    "User1 should have " + daiTokens2 + " dai, instead has " + (await dai.balanceOf(user1)),
                );
                assert.equal(
                    await yDai1.balanceOf(user1),
                    0,
                    "User2 should have no yDai left, instead has " + (await yDai1.balanceOf(user1)),
                );
            });
        });
    });
});