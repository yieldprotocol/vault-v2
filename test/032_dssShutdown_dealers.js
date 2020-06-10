// External
const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const End = artifacts.require('End');
const Chai = artifacts.require('Chai');

// Common
const ChaiOracle = artifacts.require('ChaiOracle');
const WethOracle = artifacts.require('WethOracle');
const Treasury = artifacts.require('Treasury');

// YDai
const YDai = artifacts.require('YDai');
const Dealer = artifacts.require('Dealer');

// Peripheral
const Splitter = artifacts.require('MockSplitter');
const DssShutdown = artifacts.require('DssShutdown');

const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('DssShutdown - Treasury', async (accounts) =>  {
    let [ owner, user1, user2 ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let pot;
    let end;
    let chai;
    let chaiOracle;
    let wethOracle;
    let treasury;
    let yDai1;
    let yDai2;
    let wethDealer;
    let splitter;
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
    let maturity1;
    let maturity2;

    const tag  = divRay(toRay(1), spot); // TODO: Test with tag different than initial value
    const fix  = divRay(toRay(1), spot); // TODO: Test with fix different from tag

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        // Setup vat
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        weth = await Weth.new({ from: owner });
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        await vat.file(ilk, spotName, spot, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); // TODO: Why can't we specify `, { from: owner }`?
        await vat.fold(ilk, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        // Setup pot
        pot = await Pot.new(vat.address);
        await pot.setChi(chi, { from: owner });

        // Setup end
        end = await End.new({ from: owner });
        await end.file(web3.utils.fromAscii("vat"), vat.address);

        // Permissions
        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.rely(pot.address, { from: owner });
        await vat.rely(end.address, { from: owner });

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
            { from: owner },
        );

        // Setup Oracle
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

        // Setup wethDealer
        wethDealer = await Dealer.new(
            treasury.address,
            dai.address,
            weth.address,
            wethOracle.address,
            WETH,
            { from: owner },
        );
        await treasury.grantAccess(wethDealer.address, { from: owner });

        // Setup chaiDealer
        chaiDealer = await Dealer.new(
            treasury.address,
            dai.address,
            chai.address,
            chaiOracle.address,
            CHAI,
            { from: owner },
        );
        await treasury.grantAccess(chaiDealer.address, { from: owner });

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai1 = await YDai.new(
            vat.address,
            pot.address,
            treasury.address,
            maturity1,
            "Name",
            "Symbol",
            { from: owner },
        );
        await wethDealer.addSeries(yDai1.address, { from: owner });
        await chaiDealer.addSeries(yDai1.address, { from: owner });
        await yDai1.grantAccess(wethDealer.address, { from: owner });
        await yDai1.grantAccess(chaiDealer.address, { from: owner });
        await treasury.grantAccess(yDai1.address, { from: owner });

        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai2 = await YDai.new(
            vat.address,
            pot.address,
            treasury.address,
            maturity2,
            "Name2",
            "Symbol2",
            { from: owner },
        );
        await wethDealer.addSeries(yDai2.address, { from: owner });
        await chaiDealer.addSeries(yDai2.address, { from: owner });
        await yDai2.grantAccess(wethDealer.address, { from: owner })
        await yDai2.grantAccess(chaiDealer.address, { from: owner });
        await treasury.grantAccess(yDai2.address, { from: owner });

        // Setup Splitter
        splitter = await Splitter.new(
            treasury.address,
            wethDealer.address,
            { from: owner },
        );
        await wethDealer.grantAccess(splitter.address, { from: owner });
        await treasury.grantAccess(splitter.address, { from: owner });

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
            wethDealer.address,
            chaiDealer.address,
            { from: owner },
        );
        await wethDealer.grantAccess(dssShutdown.address, { from: owner });
        await chaiDealer.grantAccess(dssShutdown.address, { from: owner });
        await treasury.registerDssShutdown(dssShutdown.address, { from: owner });
        await yDai1.grantAccess(dssShutdown.address, { from: owner });
        await yDai2.grantAccess(dssShutdown.address, { from: owner });

        // Testing permissions
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });
        await treasury.grantAccess(owner, { from: owner });
        await end.rely(owner, { from: owner });       // `owner` replaces MKR governance
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    /* it("get the size of the contract", async() => {
        console.log();
        console.log("·--------------------|------------------|------------------|------------------·");
        console.log("|  Contract          ·  Bytecode        ·  Deployed        ·  Constructor     |");
        console.log("·····················|··················|··················|···················");

        const bytecode = wethDealer.constructor._json.bytecode;
        const deployed = wethDealer.constructor._json.deployedBytecode;
        const sizeOfB  = bytecode.length / 2;
        const sizeOfD  = deployed.length / 2;
        const sizeOfC  = sizeOfB - sizeOfD;
        console.log(
            "|  " + (wethDealer.constructor._json.contractName).padEnd(18, ' ') +
            "|" + ("" + sizeOfB).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfD).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfC).padStart(16, ' ') + "  |");
        console.log("·--------------------|------------------|------------------|------------------·");
        console.log();
    }); */

    it("does not attempt to settle treasury debt until Dss shutdown initiated", async() => {
        await expectRevert(
            dssShutdown.settleTreasury({ from: owner }),
            "DssShutdown: End.sol not caged",
        );
    });

    describe("with posted weth and borrowed yDai", () => {
        beforeEach(async() => {
            await weth.deposit({ from: user1, value: wethTokens });
            await weth.approve(wethDealer.address, wethTokens, { from: user1 });
            await wethDealer.post(user1, wethTokens, { from: user1 });

            await weth.deposit({ from: user2, value: wethTokens });
            await weth.approve(wethDealer.address, wethTokens, { from: user2 });
            await wethDealer.post(user2, wethTokens, { from: user2 });

            await weth.deposit({ from: user2, value: 1 });
            await weth.approve(wethDealer.address, 1, { from: user2 });
            await wethDealer.post(user2, 1, { from: user2 });

            await wethDealer.borrow(maturity1, user2, daiTokens, { from: user2 });

            assert.equal(
                await weth.balanceOf(user1),
                0,
                'User1 should have no weth',
            );
            assert.equal(
                await weth.balanceOf(user2),
                0,
                'User2 should have no weth',
            );
        });

        describe("with Dss shutdown initiated and treasury settled", () => {
            beforeEach(async() => {
                await end.cage({ from: owner });
                await end.setTag(ilk, tag, { from: owner });
                await end.setDebt(1, { from: owner });
                await end.setFix(ilk, fix, { from: owner });
                await dssShutdown.settleTreasury({ from: owner });
                await dssShutdown.cashSavings({ from: owner });
            });

            it("weth cannot be withdrawn if debt remains", async() => {
                await expectRevert(
                    dssShutdown.withdraw(WETH, user2, { from: user2 }),
                    'DssShutdown: Settle all positions first',
                );
            });

            it("allows user to withdraw weth when no debt remains", async() => {
                await dssShutdown.withdraw(WETH, user1, { from: user1 });

                assert.equal(
                    await weth.balanceOf(user1),
                    wethTokens.toString(),
                    'User1 should have ' + wethTokens.toString() + ' weth wei',
                );
            });

            it("users can be forced to withdraw weth when no debt remains", async() => {
                await dssShutdown.withdraw(WETH, user1, { from: owner });

                assert.equal(
                    await weth.balanceOf(user1),
                    wethTokens.toString(),
                    'User1 should have ' + wethTokens.toString() + ' weth wei',
                );
            });
        });
    });
});