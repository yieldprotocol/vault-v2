const helper = require('ganache-time-traveler');
const { expectRevert } = require('@openzeppelin/test-helpers');
const { daiDebt, WETH, daiTokens1: daiTokens, wethTokens1: wethTokens, chaiTokens1: chaiTokens, spot, toRay, mulRay, divRay } = require('./shared/utils');
const { setupMaker, newTreasury, newController, newYDai, newUnwind, newLiquidations } = require("./shared/fixtures");

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
    let treasury;
    let yDai1;
    let yDai2;
    let controller;
    let liquidations;
    let unwind;

    let snapshot;
    let snapshotId;

    let maturity1;
    let maturity2;

    const tag  = divRay(toRay(0.9), spot);
    const taggedWeth = mulRay(daiTokens, tag);
    const fix  = divRay(toRay(1.1), spot);
    const fixedWeth = mulRay(daiTokens, fix);

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
            chai,
            end,
        } = await setupMaker());
        await vat.hope(daiJoin.address, { from: owner });

        treasury = await newTreasury();
        await treasury.orchestrate(owner, { from: owner });
        controller = await newController();

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai1 = await newYDai(maturity1, "Name1", "Symbol1");
        yDai2 = await newYDai(maturity2, "Name2", "Symbol2");

        // Setup Liquidations
        liquidations = await newLiquidations();

        // Setup Unwind
        unwind = await newUnwind();
        await yDai1.orchestrate(unwind.address);
        await yDai2.orchestrate(unwind.address);

        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });
        await end.rely(owner, { from: owner });       // `owner` replaces MKR governance
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

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
