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
    let [ owner, user ] = accounts;
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
    let dealer;
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

    const tag  = divRay(toRay(0.9), spot);
    const taggedWeth = mulRay(daiTokens, tag);
    const fix  = divRay(toRay(1.1), spot);
    const fixedWeth = mulRay(daiTokens, fix);

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

        // Setup dealer
        dealer = await Dealer.new(
            treasury.address,
            dai.address,
            weth.address,
            wethOracle.address,
            chai.address,
            chaiOracle.address,
            { from: owner },
        );
        await treasury.grantAccess(dealer.address, { from: owner });

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
        await dealer.addSeries(yDai1.address, { from: owner });
        await yDai1.grantAccess(dealer.address, { from: owner });
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
        await dealer.addSeries(yDai2.address, { from: owner });
        await yDai2.grantAccess(dealer.address, { from: owner })
        await treasury.grantAccess(yDai2.address, { from: owner });

        // Setup Splitter
        splitter = await Splitter.new(
            treasury.address,
            dealer.address,
            { from: owner },
        );
        await dealer.grantAccess(splitter.address, { from: owner });
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
            dealer.address,
            { from: owner },
        );
        await dealer.grantAccess(dssShutdown.address, { from: owner });
        await treasury.grantAccess(dssShutdown.address, { from: owner });
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

        const bytecode = dealer.constructor._json.bytecode;
        const deployed = dealer.constructor._json.deployedBytecode;
        const sizeOfB  = bytecode.length / 2;
        const sizeOfD  = deployed.length / 2;
        const sizeOfC  = sizeOfB - sizeOfD;
        console.log(
            "|  " + (dealer.constructor._json.contractName).padEnd(18, ' ') +
            "|" + ("" + sizeOfB).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfD).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfC).padStart(16, ' ') + "  |");
        console.log("·--------------------|------------------|------------------|------------------·");
        console.log();
    }); */

    describe("with posted weth", () => {
        beforeEach(async() => {
            await weth.deposit({ from: owner, value: wethTokens });
            await weth.transfer(treasury.address, wethTokens, { from: owner });
            await treasury.pushWeth({ from: owner });

            assert.equal(
                (await vat.urns(ilk, treasury.address)).ink,
                wethTokens.toString(),
                'Treasury should have ' + wethTokens.toString() + ' weth wei as collateral',
            );
        });

        /* it("does not allow to shutdown if MakerDAO is live", async() => {
            await expectRevert(
                dssShutdown.shutdown({ from: owner }),
                "DssShutdown: MakerDAO not shutting down",
            );
        }); */

        describe("with Dss shutdown initiated and tag defined", () => {
            beforeEach(async() => {
                await end.cage({ from: owner });
                await end.setTag(ilk, tag, { from: owner });
            });

            /* it("allows to shutdown", async() => {
                dssShutdown.shutdown({ from: owner });
                assert.equal(
                    await treasury.live.call(),
                    false,
                    'Treasury should not be live',
                );
                assert.equal(
                    await dealer.live.call(),
                    false,
                    'Dealer should not be live',
                );
                assert.equal(
                    await dssShutdown.live.call(),
                    false,
                    'DssShutdown should be activated',
                );
            }); */

            describe("with yDai in shutdown", () => {
                beforeEach(async() => {
                    // await dssShutdown.shutdown({ from: owner });
                });

                it("allows to free system collateral without debt", async() => {
                    await dssShutdown.settleTreasury({ from: owner });

                    assert.equal(
                        await weth.balanceOf(dssShutdown.address, { from: owner }),
                        wethTokens.toString(),
                        'Treasury should have ' + wethTokens.toString() + ' weth in hand, instead has ' + (await weth.balanceOf(dssShutdown.address, { from: owner })),
                    );
                });
            });
        });

        describe("with debt", () => {
            beforeEach(async() => {
                await treasury.pullDai(owner, daiTokens, { from: owner });
                assert.equal(
                    (await vat.urns(ilk, treasury.address)).art,
                    daiDebt.toString(),
                    'Treasury should have ' + daiDebt.toString() + ' dai debt.',
                );
                assert.equal(
                    await treasury.debt(),
                    daiTokens.toString(),
                    'Treasury should have ' + daiTokens.toString() + ' dai debt (in Dai).',
                );

                // Adding some extra unlocked collateral
                await weth.deposit({ from: owner, value: 1 });
                await weth.transfer(treasury.address, 1, { from: owner });
                await treasury.pushWeth({ from: owner });
            });

            describe("with shutdown initiated", () => {
                beforeEach(async() => {
                    await end.cage({ from: owner });
                    await end.setTag(ilk, tag, { from: owner });
                    // await dssShutdown.shutdown({ from: owner });
                });


                it("allows to settle treasury debt", async() => {
                    await dssShutdown.settleTreasury({ from: owner });

                    assert.equal(
                        await weth.balanceOf(dssShutdown.address, { from: owner }),
                        wethTokens.sub(taggedWeth).add(1).toString(),
                        'DssShutdown should have ' + wethTokens.sub(taggedWeth).add(1).add(1) + ' weth in hand, instead has ' + (await weth.balanceOf(dssShutdown.address, { from: owner })),
                    );
                });
            });
        });

        describe("with savings", () => {
            beforeEach(async() => {
                // Borrow some dai
                await weth.deposit({ from: owner, value: wethTokens});
                await weth.approve(wethJoin.address, wethTokens, { from: owner });
                await wethJoin.join(owner, wethTokens, { from: owner });
                await vat.frob(ilk, owner, owner, owner, wethTokens, daiDebt, { from: owner });
                await daiJoin.exit(owner, daiTokens, { from: owner });

                await dai.transfer(treasury.address, daiTokens, { from: owner });
                await treasury.pushDai({ from: owner });

                assert.equal(
                    await chai.balanceOf(treasury.address),
                    chaiTokens.toString(),
                    'Treasury should have ' + daiTokens.toString() + ' savings (as chai).',
                );
            });

            describe("with Dss shutdown initiated and fix defined", () => {
                beforeEach(async() => {
                    // End.sol needs to have weth somehow, for example by settling some debt
                    await vat.hope(daiJoin.address, { from: user });
                    await vat.hope(wethJoin.address, { from: user });
                    await weth.deposit({ from: user, value: wethTokens.mul(2)});
                    await weth.approve(wethJoin.address, wethTokens.mul(2), { from: user });
                    await wethJoin.join(user, wethTokens.mul(2), { from: user });
                    await vat.frob(ilk, user, user, user, wethTokens.mul(2), daiDebt.mul(2), { from: user });
                    await daiJoin.exit(user, daiTokens.mul(2), { from: user });

                    await end.cage({ from: owner });
                    await end.setTag(ilk, tag, { from: owner });
                    await end.setDebt(1, { from: owner });
                    await end.setFix(ilk, fix, { from: owner });

                    // Settle some random guy's debt for end.sol to have weth
                    await end.skim(ilk, user, { from: user });

                    await dssShutdown.shutdown({ from: owner });
                });

                it("allows to cash dai for weth", async() => {
                    assert.equal(
                        await vat.gem(ilk, dssShutdown.address),
                        0,
                        'DssShutdown should have no weth in WethJoin',
                    );

                    await dssShutdown.cashSavings({ from: owner });

                    // Fun fact, MakerDAO rounds in your favour when determining how much collateral to take to settle your debt.
                    assert.equal(
                        await chai.balanceOf(treasury.address),
                        0,
                        'Treasury should have no savings (as chai).',
                    );
                    assert.equal(
                        await weth.balanceOf(dssShutdown.address, { from: owner }),
                        fixedWeth.toString(), // TODO: Unpack the calculations and round the same way in the tests for parameterization
                        'DssShutdown should have ' + fixedWeth.toString() + ' weth in hand, instead has ' + (await weth.balanceOf(dssShutdown.address, { from: owner })),
                    );
                });
            });
        });
    });
});