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
const Liquidations = artifacts.require('Liquidations');
const EthProxy = artifacts.require('EthProxy');
const Unwind = artifacts.require('Unwind');

const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('Unwind - DSS Skim', async (accounts) =>  {
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
    let gasToken;
    let treasury;
    let yDai1;
    let yDai2;
    let dealer;
    let liquidations;
    let ethProxy;
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
    let rate  = toRay(1.25);
    let chi = toRay(1.2);
    const daiDebt = toWad(120);
    const daiTokens = mulRay(daiDebt, rate);
    const wethTokens = divRay(daiTokens, spot);
    const chaiTokens = divRay(daiTokens, chi);
    const yDaiTokens = daiTokens;
    let maturity1;
    let maturity2;

    const tag  = divRay(toRay(1.0), spot); // Irrelevant to the final users
    const fix  = divRay(toRay(1.0), mulRay(spot, toRay(1.1)));
    const fixedWeth = mulRay(daiTokens, fix);

    const auctionTime = 3600; // One hour

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
        await dealer.post(WETH, user, user, wethTokens, { from: user });
    }

    // Convert eth to chai and post it to yDai
    // This function shadows and uses global variables, careful.
    async function postChai(user, chaiTokens){
        await getChai(user, chaiTokens);
        await chai.approve(treasury.address, chaiTokens, { from: user });
        await dealer.post(CHAI, user, user, chaiTokens, { from: user });
    }

    // Add a new yDai series
    // This function uses global variables, careful.
    async function shutdown(){
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

        // Setup Dealer
        dealer = await Dealer.new(
            vat.address,
            weth.address,
            dai.address,
            pot.address,
            chai.address,
            gasToken.address,
            treasury.address,
            { from: owner },
        );
        await treasury.orchestrate(dealer.address, { from: owner });

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
        await dealer.addSeries(yDai1.address, { from: owner });
        await yDai1.orchestrate(dealer.address, { from: owner });
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
        await dealer.addSeries(yDai2.address, { from: owner });
        await yDai2.orchestrate(dealer.address, { from: owner });
        await treasury.orchestrate(yDai2.address, { from: owner });

        // Setup EthProxy
        ethProxy = await EthProxy.new(
            weth.address,
            treasury.address,
            dealer.address,
            { from: owner },
        );

        // Setup Liquidations
        liquidations = await Liquidations.new(
            dai.address,
            treasury.address,
            dealer.address,
            auctionTime,
            { from: owner },
        );
        await dealer.orchestrate(liquidations.address, { from: owner });
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
            dealer.address,
            liquidations.address,
            { from: owner },
        );
        await treasury.orchestrate(unwind.address, { from: owner });
        await treasury.registerUnwind(unwind.address, { from: owner });
        await dealer.orchestrate(unwind.address, { from: owner });
        await yDai1.orchestrate(unwind.address, { from: owner });
        await yDai2.orchestrate(unwind.address, { from: owner });
        await unwind.addSeries(yDai1.address, { from: owner });
        await unwind.addSeries(yDai2.address, { from: owner });
        await liquidations.orchestrate(unwind.address, { from: owner });

        // Tests setup
        await pot.setChi(chi, { from: owner });
        await vat.fold(WETH, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });

        await end.rely(owner, { from: owner });       // `owner` replaces MKR governance
        await treasury.orchestrate(owner, { from: owner });
        await yDai1.orchestrate(owner, { from: owner });
        await yDai2.orchestrate(owner, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("does not allow to settle users if treasury not settled and cashed", async() => {
        await expectRevert(
            unwind.skimDssShutdown(user3, { from: owner }),
            "Unwind: Not ready",
        );
    });

    describe("with chai savings", () => {
        beforeEach(async() => {
            await getChai(owner, chaiTokens.mul(10));
            await chai.transfer(treasury.address, chaiTokens.mul(10), { from: owner });
            // profit = 10 dai * fix (in weth)
        });

        it("chai savings are added to profits", async() => {
            await shutdown();
            await unwind.skimDssShutdown(user3, { from: owner });

            assert.equal(
                await weth.balanceOf(user3),
                fixedWeth.mul(10).add(9).toString(), // TODO: Check this correction factor
                'User3 should have ' + fixedWeth.mul(10).add(9).toString() + ' weth wei, instead has ' + (await weth.balanceOf(user3)),
            );
            // profit = 10 dai * fix (in weth)
        });

        it("chai held as collateral doesn't count as profits", async() => {
            await postChai(user2, chaiTokens);

            await shutdown();
            await unwind.skimDssShutdown(user3, { from: owner });

            assert.equal(
                await weth.balanceOf(user3),
                fixedWeth.mul(10).add(9).toString(), // TODO: Check this correction factor
                'User3 should have ' + fixedWeth.mul(10).add(9).toString() + ' weth wei',
            );
            // profit = 10 dai * fix (in weth)
        });

        it("unredeemed yDai and dealer weth debt cancel each other", async() => {
            await postWeth(user2, wethTokens);
            await dealer.borrow(WETH, await yDai1.maturity(), user2, user2, daiTokens, { from: user2 }); // dealer debt assets == yDai liabilities 

            await shutdown();
            await unwind.skimDssShutdown(user3, { from: owner });

            assert.equal(
                await weth.balanceOf(user3),
                fixedWeth.mul(10).add(9).toString(), // TODO: Check this correction factor
                'User3 should have ' + fixedWeth.mul(10).add(9).toString() + ' weth wei',
            );
            // profit = 10 dai * fix (in weth)
        });

        it("unredeemed yDai and dealer chai debt cancel each other", async() => {
            await postChai(user2, chaiTokens);
            await dealer.borrow(CHAI, await yDai1.maturity(), user2, user2, daiTokens, { from: user2 }); // dealer debt assets == yDai liabilities 

            await shutdown();
            await unwind.skimDssShutdown(user3, { from: owner });

            assert.equal(
                await weth.balanceOf(user3),
                fixedWeth.mul(10).add(9).toString(), // TODO: Check this correction factor
                'User3 should have ' + fixedWeth.mul(10).add(9).toString() + ' weth wei',
            );
            // profit = 10 dai * fix (in weth)
        });

        describe("with dai debt", () => {
            beforeEach(async() => {
                await treasury.pullDai(owner, daiTokens, { from: owner });
                // profit = 9 chai
            });
    
            it("dai debt is deduced from profits", async() => {
                await shutdown();
                await unwind.skimDssShutdown(user3, { from: owner });
    
                assert.equal(
                    await weth.balanceOf(user3),
                    fixedWeth.mul(9).add(8).toString(), // TODO: Check this correction factor
                    'User3 should have ' + fixedWeth.mul(9).add(8).toString() + ' weth wei, instead has ' + (await weth.balanceOf(user3)),
                );
            });
        });

        describe("after maturity, with a rate increase", () => {
            // Set rate to 1.5
            const rateIncrease = toRay(0.25);
            const rate0 = rate;
            const rate1 = rate.add(rateIncrease);

            const rateDifferential = divRay(rate1, rate0);

            beforeEach(async() => {
                await postWeth(user2, wethTokens);
                await dealer.borrow(WETH, await yDai1.maturity(), user2, user2, daiTokens, { from: user2 }); // dealer debt assets == yDai liabilities 

                await postChai(user2, chaiTokens);
                await dealer.borrow(CHAI, await yDai1.maturity(), user2, user2, daiTokens, { from: user2 }); // dealer debt assets == yDai liabilities 
                // profit = 10 chai

                // yDai matures
                await helper.advanceTime(1000);
                await helper.advanceBlock();
                await yDai1.mature();

                await vat.fold(WETH, vat.address, rateIncrease, { from: owner });
                // profit = 10 chai + 1 chai * (rate1/rate0 - 1)
            });

            it("there is an extra profit only from weth debt", async() => {
                await shutdown();
                await unwind.skimDssShutdown(user3, { from: owner });

                // TODO: Check this correction factor
                const expectedProfit = fixedWeth.mul(10).add(9).add(mulRay(fixedWeth, rateDifferential.sub(toRay(1))));
    
                assert.equal(
                    await weth.balanceOf(user3),
                    expectedProfit.toString(),
                    'User3 should have ' + expectedProfit.toString() + ' chai wei, instead has ' + (await weth.balanceOf(user3)),
                );
            });
        });

        describe("after maturity, with a rate increase", () => {
            // Set rate to 1.5
            const rateIncrease = toRay(0.25);
            const rate0 = rate;
            const rate1 = rate.add(rateIncrease);
            const rate2 = rate1.add(rateIncrease);

            const rateDifferential1 = divRay(rate2, rate0);
            const rateDifferential2 = divRay(rate2, rate1);

            beforeEach(async() => {
                await postWeth(user2, wethTokens);
                await dealer.borrow(WETH, await yDai1.maturity(), user2, user2, daiTokens, { from: user2 }); // dealer debt assets == yDai liabilities 

                await postWeth(user2, wethTokens);
                await dealer.borrow(WETH, await yDai2.maturity(), user2, user2, daiTokens, { from: user2 }); // dealer debt assets == yDai liabilities 

                await postChai(user2, chaiTokens);
                await dealer.borrow(CHAI, await yDai1.maturity(), user2, user2, daiTokens, { from: user2 }); // dealer debt assets == yDai liabilities 
                // profit = 10 chai

                // yDai1 matures
                await helper.advanceTime(1000);
                await helper.advanceBlock();
                await yDai1.mature();

                await vat.fold(WETH, vat.address, rateIncrease, { from: owner });

                // profit = 10 chai + 1 chai * (rate1/rate0 - 1)

                // yDai2 matures
                await helper.advanceTime(2000);
                await helper.advanceBlock();
                await yDai2.mature();

                await vat.fold(WETH, vat.address, rateIncrease, { from: owner });
                // profit = 10 chai + 1 chai * (rate2/rate0 - 1) + 1 chai * (rate2/rate1 - 1)
            });

            it("profit is acummulated from several series", async() => {
                await shutdown();
                await unwind.skimDssShutdown(user3, { from: owner });

                // TODO: Check this correction factor
                const expectedProfit = fixedWeth.mul(10).add(9)
                    .add(mulRay(fixedWeth, rateDifferential1.sub(toRay(1))))  // yDai1
                    .add(mulRay(fixedWeth, rateDifferential2.sub(toRay(1)))); // yDai2
    
                assert.equal(
                    await weth.balanceOf(user3),
                    expectedProfit.toString(),
                    'User3 should have ' + expectedProfit.toString() + ' chai wei, instead has ' + (await weth.balanceOf(user3)),
                );
            });
        });
    });
});