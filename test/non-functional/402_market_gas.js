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
const Dealer = artifacts.require('Dealer');

// Peripheral
const EthProxy = artifacts.require('EthProxy');
const Unwind = artifacts.require('Unwind');
const Market = artifacts.require('Market');

// Mocks
const FlashMinterMock = artifacts.require('FlashMinterMock');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');
const { BN, expectEvent, expectRevert } = require('@openzeppelin/test-helpers');
const { assert, expect } = require('chai');

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
    let gasToken;
    let treasury;
    let yDai1;
    let yDai2;
    let dealer;
    let splitter;
    let market;
    let flashMinter;

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

    const daiReserves = daiTokens1;
    const yDaiReserves = yDaiTokens1;

    let maturity;

    const results = new Set();
    results.add(['trade', 'daiReserves', 'yDaiReserves', 'tokensIn', 'tokensOut']);

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
            dai.address,
            yDai1.address,
            { from: owner }
        );

        // Test setup
        
        // Increase the rate accumulator
        await vat.fold(ilk, vat.address, subBN(rate1, toRay(1)), { from: owner }); // Fold only the increase from 1.0
        await pot.setChi(chi1, { from: owner }); // Set the savings accumulator

        // Allow owner to mint yDai the sneaky way, without recording a debt in dealer
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

    describe("with liquidity", () => {
        beforeEach(async() => {
            await getDai(user1, daiReserves)
            await yDai1.mint(user1, yDaiReserves, { from: owner });
    
            await dai.approve(market.address, daiReserves, { from: user1 });
            await yDai1.approve(market.address, yDaiReserves, { from: user1 });
            await market.init(daiReserves, yDaiReserves, { from: user1 });
        });

        it("sells dai", async() => {
            const tradeSize = toWad(1).div(1000);
            await getDai(from, daiTokens1);

            await market.addDelegate(operator, { from: from });
            await dai.approve(market.address, tradeSize, { from: from });
            await market.sellDai(from, to, tradeSize, { from: operator });

            const yDaiOut = new BN(await yDai1.balanceOf(to));

            results.add(['sellDai', daiReserves, yDaiReserves, tradeSize, yDaiOut]);
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

        it("buys yDai", async() => {
            const tradeSize = toWad(1).div(1000);
            await getDai(from, daiTokens1.div(1000));

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