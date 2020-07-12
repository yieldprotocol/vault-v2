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
const Liquidations = artifacts.require('Liquidations');
const EthProxy = artifacts.require('EthProxy');
const Unwind = artifacts.require('Unwind');

const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('Unwind - Treasury', async (accounts) =>  {
    let [ owner, user ] = accounts;
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

    const auctionTime = 3600; // One hour

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

        // Setup Controller
        controller = await Controller.new(
            vat.address,
            weth.address,
            dai.address,
            pot.address,
            chai.address,
            gasToken.address,
            treasury.address,
            { from: owner },
        );
        await treasury.orchestrate(controller.address, { from: owner });

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
        await controller.addSeries(yDai1.address, { from: owner });
        await yDai1.orchestrate(controller.address, { from: owner });
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
        await controller.addSeries(yDai2.address, { from: owner });
        await yDai2.orchestrate(controller.address, { from: owner });
        await treasury.orchestrate(yDai2.address, { from: owner });

        // Setup EthProxy
        ethProxy = await EthProxy.new(
            weth.address,
            treasury.address,
            controller.address,
            { from: owner },
        );

        // Setup Liquidations
        liquidations = await Liquidations.new(
            dai.address,
            treasury.address,
            controller.address,
            auctionTime,
            { from: owner },
        );
        await controller.orchestrate(liquidations.address, { from: owner });
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
            controller.address,
            liquidations.address,
            { from: owner },
        );
        await treasury.orchestrate(unwind.address, { from: owner });
        await treasury.registerUnwind(unwind.address, { from: owner });
        await controller.orchestrate(unwind.address, { from: owner });
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
        await treasury.orchestrate(owner, { from: owner });
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

        const bytecode = controller.constructor._json.bytecode;
        const deployed = controller.constructor._json.deployedBytecode;
        const sizeOfB  = bytecode.length / 2;
        const sizeOfD  = deployed.length / 2;
        const sizeOfC  = sizeOfB - sizeOfD;
        console.log(
            "|  " + (controller.constructor._json.contractName).padEnd(18, ' ') +
            "|" + ("" + sizeOfB).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfD).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfC).padStart(16, ' ') + "  |");
        console.log("·--------------------|------------------|------------------|------------------·");
        console.log();
    }); */

    describe("with posted weth", () => {
        beforeEach(async() => {
            await weth.deposit({ from: owner, value: wethTokens });
            await weth.approve(treasury.address, wethTokens, { from: owner });
            await treasury.pushWeth(owner, wethTokens, { from: owner });

            assert.equal(
                (await vat.urns(WETH, treasury.address)).ink,
                wethTokens.toString(),
                'Treasury should have ' + wethTokens.toString() + ' weth wei as collateral',
            );
        });

        it("does not allow to unwind if MakerDAO is live", async() => {
            await expectRevert(
                unwind.unwind({ from: owner }),
                "Unwind: MakerDAO not shutting down",
            );
        });

        describe("with Dss unwind initiated and tag defined", () => {
            beforeEach(async() => {
                await end.cage({ from: owner });
                await end.setTag(WETH, tag, { from: owner });
            });

            it("allows to unwind", async() => {
                await unwind.unwind({ from: owner });
                
                assert.equal(
                    await unwind.live.call(),
                    false,
                    'Unwind should be activated',
                );
                assert.equal(
                    await treasury.live.call(),
                    false,
                    'Treasury should not be live',
                );
                assert.equal(
                    await controller.live.call(),
                    false,
                    'Controller should not be live',
                );
                assert.equal(
                    await liquidations.live.call(),
                    false,
                    'Liquidations should not be live',
                );
            });

            describe("with yDai in unwind", () => {
                beforeEach(async() => {
                    await unwind.unwind({ from: owner });
                });

                it("allows to free system collateral without debt", async() => {
                    await unwind.settleTreasury({ from: owner });

                    assert.equal(
                        await weth.balanceOf(unwind.address, { from: owner }),
                        wethTokens.toString(),
                        'Treasury should have ' + wethTokens.toString() + ' weth in hand, instead has ' + (await weth.balanceOf(unwind.address, { from: owner })),
                    );
                });

                it("does not allow to push or pull assets", async() => {
                    await expectRevert(
                        treasury.pushWeth(user, wethTokens, { from: owner }),
                        "Treasury: Not available during unwind",
                    );
                    await expectRevert(
                        treasury.pushChai(user, chaiTokens, { from: owner }),
                        "Treasury: Not available during unwind",
                    );
                    await expectRevert(
                        treasury.pushDai(user, daiTokens, { from: owner }),
                        "Treasury: Not available during unwind",
                    );
                    await expectRevert(
                        treasury.pullWeth(owner, 1, { from: owner }),
                        "Treasury: Not available during unwind",
                    );
                    await expectRevert(
                        treasury.pullChai(owner, 1, { from: owner }),
                        "Treasury: Not available during unwind",
                    );
                    await expectRevert(
                        treasury.pullDai(owner, 1, { from: owner }),
                        "Treasury: Not available during unwind",
                    );
                });
            });
        });

        describe("with debt", () => {
            beforeEach(async() => {
                await treasury.pullDai(owner, daiTokens, { from: owner });
                assert.equal(
                    (await vat.urns(WETH, treasury.address)).art,
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
                await weth.approve(treasury.address, 1, { from: owner });
                await treasury.pushWeth(owner, 1, { from: owner });
            });

            describe("with unwind initiated", () => {
                beforeEach(async() => {
                    await end.cage({ from: owner });
                    await end.setTag(WETH, tag, { from: owner });
                    await unwind.unwind({ from: owner });
                });


                it("allows to settle treasury debt", async() => {
                    await unwind.settleTreasury({ from: owner });

                    assert.equal(
                        await weth.balanceOf(unwind.address, { from: owner }),
                        wethTokens.sub(taggedWeth).add(1).toString(),
                        'Unwind should have ' + wethTokens.sub(taggedWeth).add(1).add(1) + ' weth in hand, instead has ' + (await weth.balanceOf(unwind.address, { from: owner })),
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
                await vat.frob(WETH, owner, owner, owner, wethTokens, daiDebt, { from: owner });
                await daiJoin.exit(owner, daiTokens, { from: owner });

                await dai.approve(treasury.address, daiTokens, { from: owner });
                await treasury.pushDai(owner, daiTokens, { from: owner });

                assert.equal(
                    await chai.balanceOf(treasury.address),
                    chaiTokens.toString(),
                    'Treasury should have ' + daiTokens.toString() + ' savings (as chai).',
                );
            });

            describe("with Dss unwind initiated and fix defined", () => {
                beforeEach(async() => {
                    // End.sol needs to have weth somehow, for example by settling some debt
                    await vat.hope(daiJoin.address, { from: user });
                    await vat.hope(wethJoin.address, { from: user });
                    await weth.deposit({ from: user, value: wethTokens.mul(2)});
                    await weth.approve(wethJoin.address, wethTokens.mul(2), { from: user });
                    await wethJoin.join(user, wethTokens.mul(2), { from: user });
                    await vat.frob(WETH, user, user, user, wethTokens.mul(2), daiDebt.mul(2), { from: user });
                    await daiJoin.exit(user, daiTokens.mul(2), { from: user });

                    await end.cage({ from: owner });
                    await end.setTag(WETH, tag, { from: owner });
                    await end.setDebt(1, { from: owner });
                    await end.setFix(WETH, fix, { from: owner });

                    // Settle some random guy's debt for end.sol to have weth
                    await end.skim(WETH, user, { from: user });

                    await unwind.unwind({ from: owner });
                });

                it("allows to cash dai for weth", async() => {
                    assert.equal(
                        await vat.gem(WETH, unwind.address),
                        0,
                        'Unwind should have no weth in WethJoin',
                    );

                    await unwind.cashSavings({ from: owner });

                    // Fun fact, MakerDAO rounds in your favour when determining how much collateral to take to settle your debt.
                    assert.equal(
                        await chai.balanceOf(treasury.address),
                        0,
                        'Treasury should have no savings (as chai).',
                    );
                    assert.equal(
                        await weth.balanceOf(unwind.address, { from: owner }),
                        fixedWeth.toString(), // TODO: Unpack the calculations and round the same way in the tests for parameterization
                        'Unwind should have ' + fixedWeth.toString() + ' weth in hand, instead has ' + (await weth.balanceOf(unwind.address, { from: owner })),
                    );
                });
            });
        });
    });
});