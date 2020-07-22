// Peripheral
const Liquidations = artifacts.require('Liquidations');

const helper = require('ganache-time-traveler');
const { BN, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');
const { WETH, CHAI, spot, rate1, chi1, daiTokens1, wethTokens1, chaiTokens1, toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');
const { setupMaker, newTreasury, newController, newYDai, getDai, postWeth, postChai } = require("./shared/fixtures");

contract('Liquidations', async (accounts) =>  {
    let [ owner, user1, user2, user3, buyer ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let chai;
    let treasury;
    let yDai1;
    let yDai2;
    let controller;
    let liquidations;

    let snapshot;
    let snapshotId;

    const rate2  = toRay(1.5);

    const yDaiTokens1 = daiTokens1;
    let maturity1;
    let maturity2;

    const dust = '25000000000000000'; // 0.025 ETH

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
            end,
            chai
        } = await setupMaker());

        treasury = await newTreasury();
        controller = await newController();

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai1 = await newYDai(maturity1, "Name", "Symbol");
        yDai2 = await newYDai(maturity2, "Name", "Symbol");

        // Setup Liquidations
        liquidations = await Liquidations.new(
            dai.address,
            treasury.address,
            controller.address,
            { from: owner },
        );
        await controller.orchestrate(liquidations.address, { from: owner });
        await treasury.orchestrate(liquidations.address, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    describe("with posted collateral and borrowed yDai", () => {
        beforeEach(async() => {
            await postWeth(user1, wethTokens1);

            await postWeth(user2, wethTokens1.add(1));
            await controller.borrow(WETH, maturity1, user2, user2, daiTokens1, { from: user2 });

            await postWeth(user3, wethTokens1.mul(2));
            await controller.borrow(WETH, maturity1, user3, user3, daiTokens1, { from: user3 });
            await controller.borrow(WETH, maturity2, user3, user3, daiTokens1, { from: user3 });

            await postChai(user1, chaiTokens1, chi1, rate1);

            const moreChai = mulRay(chaiTokens1, toRay(1.1));
            await postChai(user2, moreChai, chi1, rate1);
            await controller.borrow(CHAI, maturity1, user2, user2, daiTokens1, { from: user2 });

            // user1 has chaiTokens1 in controller and no debt.
            // user2 has chaiTokens1 * 1.1 in controller and daiTokens1 debt.

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
            assert.equal(
                await controller.debtYDai(WETH, maturity1, user2),
                yDaiTokens1.toString(),
                'User2 should have ' + yDaiTokens1.toString() + ' maturity1 weth debt, instead has ' + (await controller.debtYDai(WETH, maturity1, user2)).toString(),
            );
        });

        it("vaults are collateralized if rates don't change", async() => {
            assert.equal(
                await controller.isCollateralized.call(WETH, user2, { from: buyer }),
                true,
                "User2 should be collateralized",
            );
            assert.equal(
                await controller.isCollateralized.call(CHAI, user2, { from: buyer }),
                true,
                "User2 should be collateralized",
            );
            assert.equal(
                await controller.isCollateralized.call(WETH, user3, { from: buyer }),
                true,
                "User3 should be collateralized",
            );
            assert.equal(
                await controller.isCollateralized.call(CHAI, user3, { from: buyer }),
                true,
                "User3 should be collateralized",
            );
        });

        it("doesn't allow to liquidate collateralized vaults", async() => {
            await expectRevert(
                liquidations.liquidate(user2, buyer, { from: buyer }),
                "Liquidations: Vault is not undercollateralized",
            );
        });

        it("doesn't allow to buy from vaults not under liquidation", async() => {
            const debt = await liquidations.debt(user2, { from: buyer });
            await expectRevert(
                liquidations.buy(buyer, user2, debt, { from: buyer }),
                "Liquidations: Vault is not in liquidation",
            );
        });

        let userDebt;
        let userCollateral;

        describe("with uncollateralized vaults", () => {
            beforeEach(async() => {
                // yDai matures
                await helper.advanceTime(1000);
                await helper.advanceBlock();
                await yDai1.mature();
            
                await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner });

                userCollateral = new BN(await controller.posted(WETH, user2, { from: buyer }));
                userDebt = (await controller.totalDebtDai.call(WETH, user2, { from: buyer }));
            });

            it("liquidations can be started", async() => {
                const event = (await liquidations.liquidate(user2, buyer, { from: buyer })).logs[0];
                const block = await web3.eth.getBlockNumber();
                now = (await web3.eth.getBlock(block)).timestamp;

                assert.equal(
                    event.event,
                    "Liquidation",
                );
                assert.equal(
                    event.args.user,
                    user2,
                );
                assert.equal(
                    event.args.started,
                    now,
                );
                assert.equal(
                    await liquidations.liquidations(user2, { from: buyer }),
                    now,
                );
                assert.equal(
                    await liquidations.collateral(user2, { from: buyer }),
                    subBN(userCollateral.toString(), dust).toString(),
                );
                assert.equal(
                    await liquidations.debt(user2, { from: buyer }),
                    userDebt.toString(),
                );
                assert.equal(
                    await controller.posted(WETH, user2, { from: buyer }),
                    0,
                );
                assert.equal(
                    await controller.totalDebtDai.call(WETH, user2, { from: buyer }),
                    0,
                );
                assert.equal(
                    await liquidations.collateral(buyer, { from: buyer }),
                    dust,
                );
            });

            describe("with started liquidations", () => {
                beforeEach(async() => {
                    await liquidations.liquidate(user2, buyer, { from: buyer });
                    await liquidations.liquidate(user3, buyer, { from: buyer });

                    userCollateral = new BN(await liquidations.collateral(user2, { from: buyer })).toString();
                    userDebt = new BN(await liquidations.debt(user2, { from: buyer })).toString();
                    await getDai(buyer, userDebt, rate2);
                });
    
                it("doesn't allow to liquidate vaults already in liquidation", async() => {
                    await expectRevert(
                        liquidations.liquidate(user2, buyer, { from: buyer }),
                        "Liquidations: Vault is already in liquidation",
                    );
                });

                it("liquidations retrieve about 1/2 of collateral at the start", async() => {
                    const liquidatorBuys = userDebt;

                    await dai.approve(treasury.address, liquidatorBuys, { from: buyer });
                    await liquidations.buy(buyer, user2, liquidatorBuys, { from: buyer });

                    assert.equal(
                        await liquidations.debt(user2, { from: buyer }),
                        0,
                        "User debt should have been erased",
                    );
                    // The buy will happen a few seconds after the start of the liquidation, so the collateral received will be slightly above the 2/3 of the total posted.
                    expect(
                        await weth.balanceOf(buyer, { from: buyer })
                    ).to.be.bignumber.gt(
                        divRay(userCollateral, toRay(2)).toString()
                    );
                    expect(
                        await weth.balanceOf(buyer, { from: buyer }),
                    ).to.be.bignumber.lt(
                        mulRay(divRay(userCollateral, toRay(2)), toRay(1.01)).toString(),
                    );
                });

                it("partial liquidations are possible", async() => {
                    const liquidatorBuys = divRay(userDebt, toRay(2));

                    await dai.approve(treasury.address, liquidatorBuys, { from: buyer });
                    await liquidations.buy(buyer, user2, liquidatorBuys, { from: buyer });

                    assert.equal(
                        await liquidations.debt(user2, { from: buyer }),
                        divRay(userDebt, toRay(2)).toString(),
                        "User debt should be " + addBN(divRay(userDebt, toRay(2)), 1) + ", instead is " + await liquidations.debt(user2, { from: buyer }),
                    );
                    // The buy will happen a few seconds after the start of the liquidation, so the collateral received will be slightly above the 1/4 of the total posted.
                    expect(
                        await weth.balanceOf(buyer, { from: buyer })
                    ).to.be.bignumber.gt(
                        divRay(userCollateral, toRay(4)).toString()
                    );
                    expect(
                        await weth.balanceOf(buyer, { from: buyer }),
                    ).to.be.bignumber.lt(
                        mulRay(divRay(userCollateral, toRay(4)), toRay(1.01)).toString(),
                    );
                });

                describe("once the liquidation time is complete", () => {
                    beforeEach(async() => {
                        await helper.advanceTime(5000); // Better to test well beyond the limit
                        await helper.advanceBlock();
                    });

                    it("liquidations retrieve all collateral", async() => {
                        const liquidatorBuys = userDebt;
    
                        await dai.approve(treasury.address, liquidatorBuys, { from: buyer });
                        await liquidations.buy(buyer, user2, liquidatorBuys, { from: buyer });
    
                        assert.equal(
                            await liquidations.debt(user2, { from: buyer }),
                            0,
                            "User debt should have been erased",
                        );
                        assert.equal(
                            await weth.balanceOf(buyer, { from: buyer }),
                            userCollateral.toString(),
                            "Liquidator should have " + userCollateral + " weth, instead has " + await weth.balanceOf(buyer, { from: buyer }),
                        );
                    });
    
                    it("partial liquidations are possible", async() => {
                        const liquidatorBuys = divRay(userDebt, toRay(2));
    
                        await dai.approve(treasury.address, liquidatorBuys, { from: buyer });
                        await liquidations.buy(buyer, user2, liquidatorBuys, { from: buyer });
    
                        assert.equal(
                            await liquidations.debt(user2, { from: buyer }),
                            divRay(userDebt, toRay(2)).toString(),
                            "User debt should have been halved",
                        );
                        assert.equal(
                            await weth.balanceOf(buyer, { from: buyer }),
                            addBN(divRay(userCollateral, toRay(2)), 1).toString(), // divRay should round up
                            "Liquidator should have " + addBN(divRay(userCollateral, toRay(2)), 1) + " weth, instead has " + await weth.balanceOf(buyer, { from: buyer }),
                        );
                    });

                    it("liquidations leaving dust revert", async() => {
                        const liquidatorBuys = subBN(userDebt, 1500); // Can be calculated programmatically from `spot` and `dust`

                        await dai.approve(treasury.address, liquidatorBuys, { from: buyer });

                        await expectRevert(
                            liquidations.buy(buyer, user2, liquidatorBuys, { from: buyer }),
                            "Liquidations: Below dust",
                        );
                    });
                });

                describe("with completed liquidations", () => {
                    beforeEach(async() => {
                        userCollateral = new BN(await liquidations.collateral(user2, { from: buyer })).toString();
                        userDebt = new BN(await liquidations.debt(user2, { from: buyer })).toString();
                        await getDai(buyer, userDebt, rate2);
    
                        await dai.approve(treasury.address, userDebt, { from: buyer });
                        await liquidations.buy(buyer, user2, userDebt, { from: buyer });
                    });
    
                    it("liquidated users can retrieve any remaining collateral", async() => {
                        const remainingWeth = (await liquidations.collateral(user2, { from: buyer })).toString();
                        await liquidations.withdraw(user2, user2, remainingWeth, { from: user2 });

                        assert.equal(
                            await liquidations.collateral(user2, { from: buyer }),
                            0,
                            "User collateral records should have been erased",
                        );
                        assert.equal(
                            await weth.balanceOf(user2, { from: buyer }),
                            remainingWeth,
                            "User should have the remaining weth",
                        );
                    });
                });
            });
        });
    });
});
