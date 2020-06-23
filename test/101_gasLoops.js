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
const ChaiOracle = artifacts.require('ChaiOracle');
const WethOracle = artifacts.require('WethOracle');
const Treasury = artifacts.require('Treasury');

// YDai
const YDai = artifacts.require('YDai');
const Dealer = artifacts.require('Dealer');

// Peripheral
const Splitter = artifacts.require('Splitter');
const EthProxy = artifacts.require('EthProxy');
const DssShutdown = artifacts.require('DssShutdown');

const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('DssShutdown - Dealers', async (accounts) =>  {
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
    let chaiOracle;
    let wethOracle;
    let treasury;
    // let yDai1;
    // let yDai2;
    let dealer;
    let splitter;
    let ethProxy;
    let dssShutdown;

    let WETH = web3.utils.fromAscii("WETH");
    let CHAI = web3.utils.fromAscii("CHAI");
    let ilk = web3.utils.fromAscii("ETH-A");
    let Line = web3.utils.fromAscii("Line");
    let spotName = web3.utils.fromAscii("spot");
    let linel = web3.utils.fromAscii("line");

    let snapshot;
    let snapshotId;

    const limits = toRad(10000);
    const spot  = toRay(1.5);
    const rate  = toRay(1.25);
    const chi = toRay(1.2);
    const daiDebt = toWad(120);
    const daiTokens = mulRay(daiDebt, rate);
    const wethTokens = divRay(daiTokens, spot);
    const chaiTokens = divRay(daiTokens, chi);
    const yDaiTokens = daiTokens;
    let maturities;

    const tag  = divRay(toRay(1.0), spot); // Irrelevant to the final users
    const fix  = divRay(toRay(1.0), mulRay(spot, toRay(1.1)));
    const fixedWeth = mulRay(daiTokens, fix);

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
        await vat.frob(ilk, user, user, user, wethTokens, daiDebt, { from: user });
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
        await weth.approve(dealer.address, wethTokens, { from: user });
        dealer.post(WETH, user, user, wethTokens, { from: user });
    }

    // Convert eth to chai and post it to yDai
    // This function shadows and uses global variables, careful.
    async function postChai(user, chaiTokens){
        await getChai(user, chaiTokens);
        await chai.approve(dealer.address, chaiTokens, { from: user });
        dealer.post(CHAI, user, user, chaiTokens, { from: user });
    }

    // Add a new yDai series
    // This function uses global variables, careful.
    async function addYDai(maturity){
        yDai = await YDai.new(
            vat.address,
            jug.address,
            pot.address,
            treasury.address,
            maturity,
            "Name",
            "Symbol",
            { from: owner },
        );
        await dealer.addSeries(yDai.address, { from: owner });
        await yDai.grantAccess(dealer.address, { from: owner });
        await treasury.grantAccess(yDai.address, { from: owner });
        await yDai.grantAccess(dssShutdown.address, { from: owner });
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

        // Setup WethOracle
        wethOracle = await WethOracle.new(vat.address, { from: owner });

        // Setup ChaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });

        // Set treasury
        treasury = await Treasury.new(
            dai.address,
            chai.address,
            chaiOracle.address,
            weth.address,
            daiJoin.address,
            wethJoin.address,
            vat.address,
            { from: owner },
        );

        // Setup Dealer
        dealer = await Dealer.new(
            treasury.address,
            dai.address,
            weth.address,
            wethOracle.address,
            chai.address,
            chaiOracle.address,
            gasToken.address,
            { from: owner },
        );
        treasury.grantAccess(dealer.address, { from: owner });

        // Setup Splitter
        splitter = await Splitter.new(
            treasury.address,
            dealer.address,
            { from: owner },
        );
        dealer.grantAccess(splitter.address, { from: owner });
        treasury.grantAccess(splitter.address, { from: owner });

        // Setup EthProxy
        ethProxy = await EthProxy.new(
            weth.address,
            gasToken.address,
            dealer.address,
            { from: owner },
        );

        // Setup DssShutdown
        dssShutdown = await DssShutdown.new(
            vat.address,
            daiJoin.address,
            weth.address,
            wethJoin.address,
            end.address,
            chai.address,
            chaiOracle.address,
            treasury.address,
            dealer.address,
            { from: owner },
        );
        await dealer.grantAccess(dssShutdown.address, { from: owner });
        await treasury.grantAccess(dssShutdown.address, { from: owner });
        await treasury.registerDssShutdown(dssShutdown.address, { from: owner });

        // Tests setup
        await pot.setChi(chi, { from: owner });
        await vat.fold(ilk, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });
        await treasury.grantAccess(owner, { from: owner });
        await end.rely(owner, { from: owner });       // `owner` replaces MKR governance
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    // TODO: Parameterize on number of maturities.
    describe("working with 8 maturities", () => {
        beforeEach(async() => {
            // Setup 8 yDai
            const block = await web3.eth.getBlockNumber();
            maturities = []; // Clear the registry for each test
            for (let i = 0; i < 8; i++) {
                const maturity = (await web3.eth.getBlock(block)).timestamp + (i*1000); 
                maturities.push(maturity);
                await addYDai(maturity);
            }

            // TODO: Test post, withdraw, borrow and repay individually.
            // TODO: Test with mature yDai as well.
            // Set the scenario
            await postWeth(user1, wethTokens);
            
            await postWeth(user2, wethTokens);
            await dealer.borrow(WETH, maturities[0], user2, daiTokens, { from: user2 });
            
            for (let i = 0; i < maturities.length; i++) {
                await postWeth(user3, wethTokens);
                await dealer.borrow(WETH, maturities[i], user3, daiTokens, { from: user3 });
            }

            // Shutdown
            await end.cage({ from: owner });
            await end.setTag(ilk, tag, { from: owner });
            await end.setDebt(1, { from: owner });
            await end.setFix(ilk, fix, { from: owner });
            await end.skim(ilk, user1, { from: owner });
            await end.skim(ilk, user2, { from: owner });
            await end.skim(ilk, owner, { from: owner });
            await dssShutdown.shutdown({ from: owner });
            await dssShutdown.settleTreasury({ from: owner });
            await dssShutdown.cashSavings({ from: owner });
        });

        it("allows user to settle weth surplus", async() => {
            await dssShutdown.settle(WETH, user1, { from: user1 });

            assert.equal(
                await weth.balanceOf(user1),
                wethTokens.toString(),
                'User1 should have ' + wethTokens.toString() + ' weth wei',
            );
        });

        it("allows user to settle weth debt", async() => {
            const fixedWeth = mulRay(daiTokens, fix);

            await dssShutdown.settle(WETH, user2, { from: user2 });

            assert.equal(
                await dealer.debtYDai(WETH, maturities[0], user2),
                0,
                'User1 should have no maturities[0] weth debt',
            );
            assert.equal(
                await weth.balanceOf(user2),
                wethTokens.sub(fixedWeth).toString(), // Each position settled substracts daiTokens * fix from the user collateral 
                'User2 should have ' + wethTokens.sub(fixedWeth) + ' weth wei, instead has ' + (await weth.balanceOf(user2)),
            );
        });

        it("allows user to settle mutiple weth positions", async() => {
            await dssShutdown.settle(WETH, user3, { from: user3 });

            assert.equal(
                await weth.balanceOf(user3), // TODO: Check about that sub(9)
                wethTokens.mul(8).sub(7).sub(fixedWeth.mul(8)).toString(), // Each position settled substracts daiTokens * fix from the user collateral 
                'User3 should have ' + wethTokens.mul(8).sub(7).sub(fixedWeth.mul(8)) + ' weth wei, instead has ' + (await weth.balanceOf(user3)),
            );
        });

        /* describe("with all yDai redeemed", () => {
            beforeEach(async() => {
                await dssShutdown.redeem(maturities[0], yDaiTokens.mul(2), user2, { from: user2 });
                await dssShutdown.redeem(maturities[0], yDaiTokens, user3, { from: user3 });
                await dssShutdown.redeem(maturities[1], yDaiTokens, user3, { from: user3 });
            });

            it("allows to extract profit", async() => {
                const profit = await weth.balanceOf(dssShutdown.address);

                await dssShutdown.profit(owner, { from: owner });

                assert.equal(
                    (await weth.balanceOf(owner)).toString(),
                    profit,
                    'Owner should have ' + profit + ' weth, instead has ' + (await weth.balanceOf(owner)),
                );
            });
        }); */
    });

    describe("working with 50 maturities", () => {
        /* beforeEach(async() => {
            // Setup 50 yDai
            const block = await web3.eth.getBlockNumber();
            maturities = []; // Clear the registry for each test
            for (let i = 0; i < 50; i++) {
                const maturity = (await web3.eth.getBlock(block)).timestamp + (i*1000); 
                maturities.push(maturity);
                await addYDai(maturity);
            }

            // Set the scenario
            await postWeth(user1, wethTokens);
            
            await postWeth(user2, wethTokens);
            await dealer.borrow(WETH, maturities[0], user2, daiTokens, { from: user2 });
            
            for (let i = 0; i < maturities.length; i++) {
                await postWeth(user3, wethTokens);
                await dealer.borrow(WETH, maturities[i], user3, daiTokens, { from: user3 });
            }

            // Shutdown
            await end.cage({ from: owner });
            await end.setTag(ilk, tag, { from: owner });
            await end.setDebt(1, { from: owner });
            await end.setFix(ilk, fix, { from: owner });
            await end.skim(ilk, user1, { from: owner });
            await end.skim(ilk, user2, { from: owner });
            await end.skim(ilk, owner, { from: owner });
            await dssShutdown.shutdown({ from: owner });
            await dssShutdown.settleTreasury({ from: owner });
            await dssShutdown.cashSavings({ from: owner });
        });

        it("allows user to settle weth surplus", async() => {
            await dssShutdown.settle(WETH, user1, { from: user1 });

            assert.equal(
                await weth.balanceOf(user1),
                wethTokens.toString(),
                'User1 should have ' + wethTokens.toString() + ' weth wei',
            );
        });

        it("allows user to settle weth debt", async() => {
            const fixedWeth = mulRay(daiTokens, fix);

            await dssShutdown.settle(WETH, user2, { from: user2 });

            assert.equal(
                await dealer.debtYDai(WETH, maturities[0], user2),
                0,
                'User1 should have no maturities[0] weth debt',
            );
            assert.equal(
                await weth.balanceOf(user2),
                wethTokens.sub(fixedWeth).toString(), // Each position settled substracts daiTokens * fix from the user collateral 
                'User2 should have ' + wethTokens.sub(fixedWeth) + ' weth wei, instead has ' + (await weth.balanceOf(user2)),
            );
        });

        it("allows user to settle mutiple weth positions", async() => {
            await dssShutdown.settle(WETH, user3, { from: user3 });

            assert.equal(
                await weth.balanceOf(user3), // TODO: Check about that sub(9)
                wethTokens.mul(50).sub(45).sub(fixedWeth.mul(50)).toString(), // Each position settled substracts daiTokens * fix from the user collateral 
                'User3 should have ' + wethTokens.mul(50).sub(45).sub(fixedWeth.mul(50)) + ' weth wei, instead has ' + (await weth.balanceOf(user3)),
            );
        }); */
    });
});