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
const Market = artifacts.require('Market');

// Mocks
const FlashMinterMock = artifacts.require('FlashMinterMock');
const YieldMathMock = artifacts.require('YieldMathMock');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');
const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { assert, expect } = require('chai');
const { hexZeroPad } = require('ethers/utils');

contract('Market', async (accounts) =>  {
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
    let treasury;
    let yDai1;
    let yDai2;
    let controller;
    let splitter;
    let market;
    let flashMinter;
    let yieldMath;

    let ilk = web3.utils.fromAscii("ETH-A");
    let Line = web3.utils.fromAscii("Line");
    let spotName = web3.utils.fromAscii("spot");
    let linel = web3.utils.fromAscii("line");

    const limits =  toRad(10000);
    const spot = toRay(1.2);

    const rate1 = toRay(1.4);
    const rate2 = toRay(1.82);
    const chi1 = toRay(1.2);

    const daiDebt1 = toWad(96);
    const daiTokens1 = mulRay(daiDebt1, rate1);
    const yDaiTokens1 = daiTokens1;
    const wethTokens1 = divRay(daiTokens1, spot);

    let maturity;

    const oneYear = '31556952';
    const k = '146235604338';
    const g = '18428297329635842000';

    // Convert eth to weth and use it to borrow `daiTokens` from MakerDAO
    // This function shadows and uses global variables, careful.
    async function getDai(user, _daiTokens){
        await vat.hope(daiJoin.address, { from: user });
        await vat.hope(wethJoin.address, { from: user });

        const _daiDebt = divRay(_daiTokens, rate1);
        const _wethTokens = divRay(_daiTokens, spot);

        await weth.deposit({ from: user, value: _wethTokens });
        await weth.approve(wethJoin.address, _wethTokens, { from: user });
        await wethJoin.join(user, _wethTokens, { from: user });
        await vat.frob(ilk, user, user, user, _wethTokens, _daiDebt, { from: user });
        await daiJoin.exit(user, _daiTokens, { from: user });
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
            dai.address,
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
            dai.address,
            yDai1.address,
            { from: owner }
        );

        // Setup YieldMathMock
        yieldMath = await YieldMathMock.new();

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

    it("get the size of the contract", async() => {
        console.log();
        console.log("    ·--------------------|------------------|------------------|------------------·");
        console.log("    |  Contract          ·  Bytecode        ·  Deployed        ·  Constructor     |");
        console.log("    ·····················|··················|··················|···················");
        
        const bytecode = market.constructor._json.bytecode;
        const deployed = market.constructor._json.deployedBytecode;
        const sizeOfB  = bytecode.length / 2;
        const sizeOfD  = deployed.length / 2;
        const sizeOfC  = sizeOfB - sizeOfD;
        console.log(
            "    |  " + (market.constructor._json.contractName).padEnd(18, ' ') +
            "|" + ("" + sizeOfB).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfD).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfC).padStart(16, ' ') + "  |");
        console.log("    ·--------------------|------------------|------------------|------------------·");
        console.log();
    });

    it("should setup market", async() => {
        const b = new BN('18446744073709551615');
        const k = b.div((new BN('126144000')));
        expect(await market.k()).to.be.bignumber.equal(k);

        const g = (new BN('999')).mul(b).div(new BN('1000')).add(new BN(1)); // Close enough
        expect(new BN(await market.g())).to.be.bignumber.equal(g);
    });

    it("adds initial liquidity", async() => {
        await getDai(user1, daiTokens1)
        await yDai1.mint(user1, yDaiTokens1, { from: owner });

        console.log("        initial liquidity...");
        console.log("        daiReserves: %d", daiTokens1.toString());
        console.log("        yDaiReserves: %d", yDaiTokens1.toString());
        console.log("        k: %d", await market.k());
        const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp);
        console.log("        timeTillMaturity: %d", (new BN(maturity).sub(t).toString()));

        await dai.approve(market.address, daiTokens1, { from: user1 });
        await yDai1.approve(market.address, yDaiTokens1, { from: user1 });
        await market.init(daiTokens1, yDaiTokens1, { from: user1 });

        // Test with https://www.desmos.com/calculator/rvmg7soarl

        // TODO: How much should this be?
        /* assert.equal(
            await market.balanceOf(user1),
            1000,
            "User1 should have 1000 liquidity tokens",
        ); */
    });

    describe("with liquidity", () => {
        beforeEach(async() => {
            const daiReserves = daiTokens1;
            const yDaiReserves = yDaiTokens1.mul(2);
            await getDai(user1, daiReserves)
            await yDai1.mint(user1, yDaiReserves, { from: owner });
    
            await dai.approve(market.address, daiReserves, { from: user1 });
            await yDai1.approve(market.address, yDaiReserves, { from: user1 });
            await market.init(daiReserves, yDaiReserves, { from: user1 });

            /* const liquidityTokens = new BN(await market.balanceOf(user1));
            const expectedLiquidityTokens = new BN(addBN(yDaiReserves, daiReserves).toString());
            expect(expectedLiquidityTokens).to.be.bignumber.gt(liquidityTokens.mul(new BN('9999')).div(new BN('10000')));
            expect(expectedLiquidityTokens).to.be.bignumber.lt(liquidityTokens.mul(new BN('10001')).div(new BN('10000'))); */
        }); // TODO: Test with reserves at different levels.

        /* it("mints liquidity tokens", async() => {
            await getDai(user1, daiTokens1)
            await yDai1.mint(user1, yDaiTokens1, { from: owner });

            await dai.approve(market.address, daiTokens1, { from: user1 });
            await yDai1.approve(market.address, yDaiTokens1, { from: user1 });
            await market.mint(daiTokens1, { from: user1 });

            assert.equal(
                await market.balanceOf(user1),
                liquidityTokens.mul(new BN('2')).toString(),
                "User1 should have " + liquidityTokens.mul(new BN('2')) + " liquidity tokens",
            );
        });

        it("burns liquidity tokens", async() => {
            const liquidityTokens = new BN(await market.balanceOf(user1, { from: user1 }));
            const toBurn = liquidityTokens.div(new BN('2'));
            await market.approve(market.address, toBurn, { from: user1 });
            await market.burn(toBurn, { from: user1 });

            assert.equal(
                await dai.balanceOf(user1),
                daiTokens1.div(2).toString(),
                "User1 should have dai tokens",
            );
            assert.equal(
                await yDai1.balanceOf(user1),
                yDaiTokens1.div(2).toString(),
                "User1 should have yDai tokens",
            );
        }); */

        it("sells yDai", async() => {
            const b = new BN('18446744073709551615');
            const r = new BN('1000000000000000000000000000');
            const oneToken = toWad(1);
            await yDai1.mint(from, oneToken, { from: owner });

            // daiOutForYDaiIn formula: https://www.desmos.com/calculator/9gi4atvazv - Set c to 1.0 to obtain Dai

            console.log("          selling yDai...");
            console.log("          daiReserves: %d", await dai.balanceOf(market.address));
            console.log("          yDaiReserves: %d", await yDai1.balanceOf(market.address));
            console.log("          yDaiIn: %d", oneToken.toString());
            console.log("          k: %d", await market.k());
            console.log("          g: %d", await market.g());
            const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp);
            console.log("          timeTillMaturity: %d", (new BN(maturity).sub(t).toString()));

            assert.equal(
                await dai.balanceOf(to),
                0,
                "'To' wallet should have no dai, instead has " + await dai.balanceOf(to),
            );

            // Test preview since we are here
            const daiOutPreview = await market.sellYDaiPreview(oneToken, { from: operator });

            await market.addDelegate(operator, { from: from });
            await yDai1.approve(market.address, oneToken, { from: from });
            await market.sellYDai(from, to, oneToken, { from: operator });

            assert.equal(
                await yDai1.balanceOf(from),
                0,
                "'From' wallet should have no yDai tokens",
            );

            const expectedDaiOut = (new BN(oneToken.toString())).mul(new BN('83990')).div(new BN('100000')); // I just hate javascript
            const daiOut = new BN(await dai.balanceOf(to));
            expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')));
            expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')));
            expect(daiOut).to.be.bignumber.gt(daiOutPreview.mul(new BN('9999')).div(new BN('10000')));
            expect(daiOut).to.be.bignumber.lt(daiOutPreview.mul(new BN('10001')).div(new BN('10000')));
        });

        it("buys dai", async() => {
            const b = new BN('18446744073709551615');
            const r = new BN('1000000000000000000000000000');
            const oneToken = toWad(1);
            await yDai1.mint(from, yDaiTokens1, { from: owner });

            // yDaiInForDaiOut formula: https://www.desmos.com/calculator/16c4dgxhst - Set c to 1.0 to obtain Dai

            console.log("          buying dai...");
            console.log("          daiReserves: %d", await dai.balanceOf(market.address));
            console.log("          yDaiReserves: %d", await yDai1.balanceOf(market.address));
            console.log("          daiOut: %d", oneToken.toString());
            console.log("          k: %d", await market.k());
            console.log("          g: %d", await market.g());
            const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp);
            console.log("          timeTillMaturity: %d", (new BN(maturity).sub(t).toString()));

            assert.equal(
                await yDai1.balanceOf(from),
                yDaiTokens1.toString(),
                "'From' wallet should have " + yDaiTokens1 + " yDai, instead has " + await yDai1.balanceOf(from),
            );

            // Test preview since we are here
            const yDaiInPreview = await market.buyDaiPreview(oneToken, { from: operator });

            await market.addDelegate(operator, { from: from });
            await yDai1.approve(market.address, yDaiTokens1, { from: from });
            await market.buyDai(from, to, oneToken, { from: operator });

            assert.equal(
                await dai.balanceOf(to),
                oneToken.toString(),
                "Receiver account should have 1 dai token",
            );

            const expectedYDaiIn = (new BN(oneToken.toString())).mul(new BN('119090')).div(new BN('100000')); // I just hate javascript
            const yDaiIn = (new BN(yDaiTokens1.toString())).sub(new BN(await yDai1.balanceOf(from)));
            expect(yDaiIn).to.be.bignumber.gt(expectedYDaiIn.mul(new BN('9999')).div(new BN('10000')));
            expect(yDaiIn).to.be.bignumber.lt(expectedYDaiIn.mul(new BN('10001')).div(new BN('10000')));
            expect(yDaiIn).to.be.bignumber.gt(yDaiInPreview.mul(new BN('9999')).div(new BN('10000')));
            expect(yDaiIn).to.be.bignumber.lt(yDaiInPreview.mul(new BN('10001')).div(new BN('10000')));
        });

        describe("with extra yDai reserves", () => {
            beforeEach(async() => {
                const additionalYDaiReserves = toWad(34.4);
                await yDai1.mint(operator, additionalYDaiReserves, { from: owner });
                await yDai1.approve(market.address, additionalYDaiReserves, { from: operator });
                await market.sellYDai(operator, operator, additionalYDaiReserves, { from: operator });
            });

            it("sells dai", async() => {
                const b = new BN('18446744073709551615');
                const r = new BN('1000000000000000000000000000');
                const oneToken = toWad(1);
                await getDai(from, daiTokens1);
    
                // yDaiOutForDaiIn formula: https://www.desmos.com/calculator/dcjuj5lmmc - Set c to 1.0 to obtain Dai
    
                console.log("          selling dai...");
                console.log("          daiReserves: %d", await dai.balanceOf(market.address));
                console.log("          yDaiReserves: %d", await yDai1.balanceOf(market.address));
                console.log("          daiIn: %d", oneToken.toString());
                console.log("          k: %d", await market.k());
                console.log("          g: %d", await market.g());
                const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp);
                console.log("          timeTillMaturity: %d", (new BN(maturity).sub(t).toString()));
    
                assert.equal(
                    await yDai1.balanceOf(to),
                    0,
                    "'To' wallet should have no yDai, instead has " + await yDai1.balanceOf(operator),
                );
    
                // Test preview since we are here
                const yDaiOutPreview = await market.sellDaiPreview(oneToken, { from: operator });
    
                await market.addDelegate(operator, { from: from });
                await dai.approve(market.address, oneToken, { from: from });
                await market.sellDai(from, to, oneToken, { from: operator });
    
                assert.equal(
                    await dai.balanceOf(from),
                    daiTokens1.sub(oneToken).toString(),
                    "'From' wallet should have " + daiTokens1.sub(oneToken) + " dai tokens",
                );
    
                const expectedYDaiOut = (new BN(oneToken.toString())).mul(new BN('129600')).div(new BN('100000')); // I just hate javascript
                const yDaiOut = new BN(await yDai1.balanceOf(to));
                // TODO: Test precision with 48 and 64 bits with this trade and reserve levels
                expect(yDaiOut).to.be.bignumber.gt(expectedYDaiOut.mul(new BN('9999')).div(new BN('10000')));
                expect(yDaiOut).to.be.bignumber.lt(expectedYDaiOut.mul(new BN('10001')).div(new BN('10000')));
                expect(yDaiOut).to.be.bignumber.gt(yDaiOutPreview.mul(new BN('9999')).div(new BN('10000')));
                expect(yDaiOut).to.be.bignumber.lt(yDaiOutPreview.mul(new BN('10001')).div(new BN('10000')));
            });
    
            it("buys yDai", async() => {
                const b = new BN('18446744073709551615');
                const r = new BN('1000000000000000000000000000');
                const oneToken = toWad(1);
                await getDai(from, daiTokens1);
    
                // daiInForYDaiOut formula: https://www.desmos.com/calculator/gko3hvn5dd - Set c to 1.0 to obtain Dai
    
                console.log("          buying yDai...");
                console.log("          daiReserves: %d", await dai.balanceOf(market.address));
                console.log("          yDaiReserves: %d", await yDai1.balanceOf(market.address));
                console.log("          yDaiOut: %d", oneToken.toString());
                console.log("          k: %d", await market.k());
                console.log("          g: %d", await market.g());
                const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp);
                console.log("          timeTillMaturity: %d", (new BN(maturity).sub(t).toString()));
    
                assert.equal(
                    await yDai1.balanceOf(to),
                    0,
                    "'To' wallet should have no yDai, instead has " + await yDai1.balanceOf(to),
                );
    
                // Test preview since we are here
                const daiInPreview = await market.buyYDaiPreview(oneToken, { from: operator });
    
                await market.addDelegate(operator, { from: from });
                await dai.approve(market.address, daiTokens1, { from: from });
                await market.buyYDai(from, to, oneToken, { from: operator });
    
                assert.equal(
                    await yDai1.balanceOf(to),
                    oneToken.toString(),
                    "'To' wallet should have 1 yDai token",
                );
    
                const expectedDaiIn = (new BN(oneToken.toString())).mul(new BN('77128')).div(new BN('100000')); // I just hate javascript
                const daiIn = (new BN(daiTokens1.toString())).sub(new BN(await dai.balanceOf(from)));
                expect(daiIn).to.be.bignumber.gt(expectedDaiIn.mul(new BN('9999')).div(new BN('10000')));
                expect(daiIn).to.be.bignumber.lt(expectedDaiIn.mul(new BN('10001')).div(new BN('10000')));
                expect(daiIn).to.be.bignumber.gt(daiInPreview.mul(new BN('9999')).div(new BN('10000')));
                expect(daiIn).to.be.bignumber.lt(daiInPreview.mul(new BN('10001')).div(new BN('10000')));
            });    
        });

        describe("once mature", () => {
            beforeEach(async() => {
                await helper.advanceTime(31556952);
                await helper.advanceBlock();
                // await yDai1.mature(); // TODO: Does it matter if the yDai is marked as mature?
            });

            it("doesn't allow trading", async() => {
                const oneToken = toWad(1);

                await expectRevert(
                    market.sellDaiPreview(oneToken, { from: operator }),
                    "Market: Too late",
                );
                await expectRevert(
                    market.sellDai(from, to, oneToken, { from: from }),
                    "Market: Too late",
                );
                await expectRevert(
                    market.buyDaiPreview(oneToken, { from: operator }),
                    "Market: Too late",
                );
                await expectRevert(
                    market.buyDai(from, to, oneToken, { from: from }),
                    "Market: Too late",
                );
                await expectRevert(
                    market.sellYDaiPreview(oneToken, { from: operator }),
                    "Market: Too late",
                );
                await expectRevert(
                    market.sellYDai(from, to, oneToken, { from: from }),
                    "Market: Too late",
                );
                await expectRevert(
                    market.buyYDaiPreview(oneToken, { from: operator }),
                    "Market: Too late",
                );
                await expectRevert(
                    market.buyYDai(from, to, oneToken, { from: from }),
                    "Market: Too late",
                );
            });
        });
    });
});