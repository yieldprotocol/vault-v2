const Market = artifacts.require("Market")
const helper = require('ganache-time-traveler');
const { BN } = require('@openzeppelin/test-helpers');
const { rate1, daiTokens1, toWad } = require('./../shared/utils');
const { setupMaker, newTreasury, newController, newYDai, getDai } = require("./../shared/fixtures");

contract('Market', async (accounts) =>  {
    let [ owner, user1, operator, from, to ] = accounts;
    let dai;
    let treasury;
    let yDai1;
    let controller;
    let market;
    
    const daiReserves = daiTokens1;
    const yDaiTokens1 = daiTokens1;
    const yDaiReserves = yDaiTokens1;

    let maturity;

    const results = new Set();
    results.add(['trade', 'daiReserves', 'yDaiReserves', 'tokensIn', 'tokensOut']);

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        ({
            vat,
            weth,
            wethJoin,
            dai,
            daiJoin,
            pot,
            jug,
            chai
        } = await setupMaker());

        treasury = await newTreasury();
        controller = await newController();
    
        // Setup yDai1
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 31556952; // One year
        yDai1 = await newYDai(maturity, "Name", "Symbol");
        await yDai1.orchestrate(owner);

        // Setup Market
        market = await Market.new(
            dai.address,
            yDai1.address,
            { from: owner }
        );
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

    describe("with liquidity", () => {
        beforeEach(async() => {
            await getDai(user1, daiReserves, rate1)
            await yDai1.mint(user1, yDaiReserves, { from: owner });
    
            await dai.approve(market.address, daiReserves, { from: user1 });
            await yDai1.approve(market.address, yDaiReserves, { from: user1 });
            await market.init(daiReserves, { from: user1 });
        });

        it("buys dai", async() => {
            const tradeSize = toWad(1).div(1000);
            await yDai1.mint(from, yDaiTokens1.div(1000), { from: owner });

            await market.addDelegate(operator, { from: from });
            await yDai1.approve(market.address, yDaiTokens1.div(1000), { from: from });
            await market.buyDai(from, to, tradeSize, { from: operator });

            const yDaiIn = (new BN(yDaiTokens1.div(1000).toString())).sub(new BN(await yDai1.balanceOf(from)));

            results.add(['buyDai', daiReserves, yDaiReserves, yDaiIn, tradeSize]);
        });

        it("sells yDai", async() => {
            const tradeSize = toWad(1).div(1000);
            await yDai1.mint(from, tradeSize, { from: owner });

            await market.addDelegate(operator, { from: from });
            await yDai1.approve(market.address, tradeSize, { from: from });
            await market.sellYDai(from, to, tradeSize, { from: operator });

            const daiOut = new BN(await dai.balanceOf(to));
            results.add(['sellYDai', daiReserves, yDaiReserves, tradeSize, daiOut]);
        });

        describe("with extra yDai reserves", () => {
            beforeEach(async() => {
                const additionalYDaiReserves = toWad(34.4);
                await yDai1.mint(operator, additionalYDaiReserves, { from: owner });
                await yDai1.approve(market.address, additionalYDaiReserves, { from: operator });
                await market.sellYDai(operator, operator, additionalYDaiReserves, { from: operator });
            });

            it("sells dai", async() => {
                const tradeSize = toWad(1).div(1000);
                await getDai(from, daiTokens1, rate1);
    
                await market.addDelegate(operator, { from: from });
                await dai.approve(market.address, tradeSize, { from: from });
                await market.sellDai(from, to, tradeSize, { from: operator });
    
                const yDaiOut = new BN(await yDai1.balanceOf(to));
    
                results.add(['sellDai', daiReserves, yDaiReserves, tradeSize, yDaiOut]);
            });

            it("buys yDai", async() => {
                const tradeSize = toWad(1).div(1000);
                await getDai(from, daiTokens1.div(1000), rate1);
    
                await market.addDelegate(operator, { from: from });
                await dai.approve(market.address, daiTokens1.div(1000), { from: from });
                await market.buyYDai(from, to, tradeSize, { from: operator });
    
                const daiIn = (new BN(daiTokens1.div(1000).toString())).sub(new BN(await dai.balanceOf(from)));
                results.add(['buyYDai', daiReserves, yDaiReserves, daiIn, tradeSize]);
            });
            
            it("prints results", async() => {
                for (line of results.values()) {
                    console.log("| " + 
                        line[0].padEnd(10, ' ') + "· " +
                        line[1].toString().padEnd(23, ' ') + "· " +
                        line[2].toString().padEnd(23, ' ') + "· " +
                        line[3].toString().padEnd(23, ' ') + "· " +
                        line[4].toString().padEnd(23, ' ') + "|");
                }
            });        
        });
    });
});
