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
const Liquidations = artifacts.require('Liquidations');
const EthProxy = artifacts.require('EthProxy');
const Unwind = artifacts.require('Unwind');

const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');
const { assert } = require('chai');

contract('Liquidations', async (accounts) =>  {
    let [ owner, user1, user2, user3, buyer ] = accounts;
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

    let WETH = web3.utils.fromAscii("ETH-A");
    let CHAI = web3.utils.fromAscii("CHAI");
    let Line = web3.utils.fromAscii("Line");
    let spotName = web3.utils.fromAscii("spot");
    let linel = web3.utils.fromAscii("line");

    let snapshot;
    let snapshotId;

    const limits = toRad(10000);
    const spot  = toRay(1.5);
    const rate1  = toRay(1.25);
    const rate2  = toRay(1.5);
    const chi = toRay(1.2);
    const daiDebt = toWad(120);
    const daiTokens = mulRay(daiDebt, rate1);
    const wethTokens = divRay(daiTokens, spot);
    const chaiTokens = divRay(daiTokens, chi);
    const yDaiTokens = daiTokens;
    let maturity1;
    let maturity2;

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        // Setup vat
        vat = await Vat.new();
        await vat.init(WETH, { from: owner });

        weth = await Weth.new({ from: owner });
        wethJoin = await GemJoin.new(vat.address, WETH, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        await vat.file(WETH, spotName, spot, { from: owner });
        await vat.file(WETH, linel, limits, { from: owner });
        await vat.file(Line, limits); 

        // Setup pot
        pot = await Pot.new(vat.address);

        // Setup jug
        jug = await Jug.new(vat.address);
        await jug.init(WETH, { from: owner }); // Set WETH duty (stability fee) to 1.0

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

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
            { from: owner },
        );

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

        // Setup controller
        controller = await Controller.new(
            vat.address,
            pot.address,
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
        await yDai2.orchestrate(controller.address, { from: owner })
        await treasury.orchestrate(yDai2.address, { from: owner });

        // Setup Liquidations
        liquidations = await Liquidations.new(
            dai.address,
            treasury.address,
            controller.address,
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
        await liquidations.orchestrate(unwind.address, { from: owner });

        // Testing permissions
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });
        await vat.hope(daiJoin.address, { from: buyer });
        await vat.hope(wethJoin.address, { from: buyer });
        await treasury.orchestrate(owner, { from: owner });
        await end.rely(owner, { from: owner });       // `owner` replaces MKR governance

        // Setup tests
        await vat.fold(WETH, vat.address, subBN(rate1, toRay(1)), { from: owner }); // Fold only the increase from 1.0
        await pot.setChi(chi, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    describe("with posted collateral and borrowed yDai", () => {
        beforeEach(async() => {
            // Weth setup
            await weth.deposit({ from: user1, value: wethTokens });
            await weth.approve(treasury.address, wethTokens, { from: user1 });
            await controller.post(WETH, user1, user1, wethTokens, { from: user1 });

            await weth.deposit({ from: user2, value: wethTokens.add(1) });
            await weth.approve(treasury.address, wethTokens.add(1), { from: user2 });
            await controller.post(WETH, user2, user2, wethTokens.add(1), { from: user2 });
            await controller.borrow(WETH, maturity1, user2, user2, daiTokens, { from: user2 });

            await weth.deposit({ from: user3, value: wethTokens.mul(2) });
            await weth.approve(treasury.address, wethTokens.mul(2), { from: user3 });
            await controller.post(WETH, user3, user3, wethTokens.mul(2), { from: user3 });
            await controller.borrow(WETH, maturity1, user3, user3, daiTokens, { from: user3 });
            await controller.borrow(WETH, maturity2, user3, user3, daiTokens, { from: user3 });

            // Chai setup
            await vat.hope(daiJoin.address, { from: user1 });
            await vat.hope(wethJoin.address, { from: user1 });

            await weth.deposit({ from: user1, value: wethTokens });
            await weth.approve(wethJoin.address, wethTokens, { from: user1 });
            await wethJoin.join(user1, wethTokens, { from: user1 });
            await vat.frob(WETH, user1, user1, user1, wethTokens, daiDebt, { from: user1 });
            await daiJoin.exit(user1, daiTokens, { from: user1 });
            await dai.approve(chai.address, daiTokens, { from: user1 });
            await chai.join(user1, daiTokens, { from: user1 });
            await chai.approve(treasury.address, chaiTokens, { from: user1 });
            await controller.post(CHAI, user1, user1, chaiTokens, { from: user1 });

            await vat.hope(daiJoin.address, { from: user2 });
            await vat.hope(wethJoin.address, { from: user2 });

            const moreDebt = mulRay(daiDebt, toRay(1.1));
            const moreDai = mulRay(daiTokens, toRay(1.1));
            const moreWeth = mulRay(wethTokens, toRay(1.1));
            const moreChai = mulRay(chaiTokens, toRay(1.1));
            await weth.deposit({ from: user2, value: moreWeth });
            await weth.approve(wethJoin.address, moreWeth, { from: user2 });
            await wethJoin.join(user2, moreWeth, { from: user2 });
            await vat.frob(WETH, user2, user2, user2, moreWeth, moreDebt, { from: user2 });
            await daiJoin.exit(user2, moreDai, { from: user2 });
            await dai.approve(chai.address, moreDai, { from: user2 });
            await chai.join(user2, moreDai, { from: user2 });
            await chai.approve(treasury.address, moreChai, { from: user2 });
            await controller.post(CHAI, user2, user2, moreChai, { from: user2 });
            await controller.borrow(CHAI, maturity1, user2, user2, daiTokens, { from: user2 });

            // user1 has chaiTokens in controller and no debt.
            // user2 has chaiTokens * 1.1 in controller and daiTokens debt.

            // Make sure that end.sol will have enough weth to cash chai savings
            await weth.deposit({ from: owner, value: wethTokens.mul(10) });
            await weth.approve(wethJoin.address, wethTokens.mul(10), { from: owner });
            await wethJoin.join(owner, wethTokens.mul(10), { from: owner });
            await vat.frob(WETH, owner, owner, owner, wethTokens.mul(10), daiDebt.mul(10), { from: owner });
            await daiJoin.exit(owner, daiTokens.mul(10), { from: owner });

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
                yDaiTokens.toString(),
                'User2 should have ' + yDaiTokens.toString() + ' maturity1 weth debt, instead has ' + (await controller.debtYDai(WETH, maturity1, user2)).toString(),
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

        describe("with uncollateralized vaults", () => {
            beforeEach(async() => {
                // yDai matures
                await helper.advanceTime(1000);
                await helper.advanceBlock();
                await yDai1.mature();
            
                await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner });
            });

            it("liquidations can be started", async() => {
                const userCollateral = new BN(await controller.posted(WETH, user2, { from: buyer }));
                const userDebt = (await controller.totalDebtDai.call(WETH, user2, { from: buyer }));
                const dust = '25000000000000000'; // 0.025 ETH
                
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
                });
    
                it("doesn't allow to liquidate vaults already in liquidation", async() => {
                    await expectRevert(
                        liquidations.liquidate(user2, buyer, { from: buyer }),
                        "Liquidations: Vault is already in liquidation",
                    );
                });

                it("liquidations retrieve about 1/2 of collateral at the start", async() => {
                    const daiTokens = (await liquidations.debt(user2, { from: buyer })).toString();
                    // console.log(daiTokens); // 180
                    const liquidatorDaiDebt = divRay(daiTokens, rate2);
                    const liquidatorWethTokens = divRay(daiTokens, spot);
                    // console.log(daiDebt.toString());
                    // wethTokens = 100 ether + 1 wei

                    await weth.deposit({ from: buyer, value: liquidatorWethTokens });
                    await weth.approve(wethJoin.address, liquidatorWethTokens, { from: buyer });
                    await wethJoin.join(buyer, liquidatorWethTokens, { from: buyer });
                    await vat.frob(WETH, buyer, buyer, buyer, liquidatorWethTokens, liquidatorDaiDebt, { from: buyer });
                    await daiJoin.exit(buyer, daiTokens, { from: buyer });

                    await dai.approve(treasury.address, daiTokens, { from: buyer });
                    await liquidations.buy(buyer, user2, daiTokens, { from: buyer });

                    assert.equal(
                        await liquidations.debt(user2, { from: buyer }),
                        0,
                        "User debt should have been erased",
                    );
                    // The buy will happen a few seconds after the start of the liquidation, so the collateral received will be slightly above the 2/3 of the total posted.
                    expect(
                        await weth.balanceOf(buyer, { from: buyer })
                    ).to.be.bignumber.gt(
                        divRay(wethTokens, toRay(2)).toString()
                    );
                    expect(
                        await weth.balanceOf(buyer, { from: buyer }),
                    ).to.be.bignumber.lt(
                        mulRay(divRay(wethTokens, toRay(2)), toRay(1.01)).toString(),
                    );
                });

                it("partial liquidations are possible", async() => {
                    const daiTokens = (await liquidations.debt(user2, { from: buyer })).toString();
                    // console.log(daiTokens); // 180
                    const liquidatorDaiDebt = divRay(daiTokens, rate2);
                    const liquidatorWethTokens = divRay(daiTokens, spot);
                    // console.log(daiDebt.toString());
                    // wethTokens = 100 ether + 1 wei

                    await weth.deposit({ from: buyer, value: liquidatorWethTokens });
                    await weth.approve(wethJoin.address, liquidatorWethTokens, { from: buyer });
                    await wethJoin.join(buyer, liquidatorWethTokens, { from: buyer });
                    await vat.frob(WETH, buyer, buyer, buyer, liquidatorWethTokens, liquidatorDaiDebt, { from: buyer });
                    await daiJoin.exit(buyer, daiTokens, { from: buyer });

                    await dai.approve(treasury.address, divRay(daiTokens, toRay(2)), { from: buyer });
                    await liquidations.buy(buyer, user2, divRay(daiTokens, toRay(2)), { from: buyer });

                    assert.equal(
                        await liquidations.debt(user2, { from: buyer }),
                        divRay(daiTokens, toRay(2)).toString(),
                        "User debt should have been halved",
                    );
                    // The buy will happen a few seconds after the start of the liquidation, so the collateral received will be slightly above the 1/4 of the total posted.
                    expect(
                        await weth.balanceOf(buyer, { from: buyer })
                    ).to.be.bignumber.gt(
                        divRay(wethTokens, toRay(4)).toString()
                    );
                    expect(
                        await weth.balanceOf(buyer, { from: buyer }),
                    ).to.be.bignumber.lt(
                        mulRay(divRay(wethTokens, toRay(4)), toRay(1.01)).toString(),
                    );
                });

                describe("once the liquidation time is complete", () => {
                    beforeEach(async() => {
                        await helper.advanceTime(5000); // Better to test well beyond the limit
                        await helper.advanceBlock();
                    });

                    it("liquidations retrieve all collateral", async() => {
                        const daiTokens = (await liquidations.debt(user2, { from: buyer })).toString();
                        const liquidatorDaiDebt = divRay(daiTokens, rate2);
                        const liquidatorWethTokens = divRay(daiTokens, spot);
                        const wethTokens = await liquidations.collateral(user2, { from: owner });
    
                        await weth.deposit({ from: buyer, value: liquidatorWethTokens });
                        await weth.approve(wethJoin.address, liquidatorWethTokens, { from: buyer });
                        await wethJoin.join(buyer, liquidatorWethTokens, { from: buyer });
                        await vat.frob(WETH, buyer, buyer, buyer, liquidatorWethTokens, liquidatorDaiDebt, { from: buyer });
                        await daiJoin.exit(buyer, daiTokens, { from: buyer });
    
                        await dai.approve(treasury.address, daiTokens, { from: buyer });
                        await liquidations.buy(buyer, user2, daiTokens, { from: buyer });
    
                        assert.equal(
                            await liquidations.debt(user2, { from: buyer }),
                            0,
                            "User debt should have been erased",
                        );
                        assert.equal(
                            await weth.balanceOf(buyer, { from: buyer }),
                            wethTokens.toString(),
                            "Liquidator should have " + wethTokens + " weth, instead has " + await weth.balanceOf(buyer, { from: buyer }),
                        );
                    });
    
                    it("partial liquidations are possible", async() => {
                        const daiTokens = (await liquidations.debt(user2, { from: buyer })).toString();
                        const liquidatorDaiDebt = divRay(daiTokens, rate2);
                        const liquidatorWethTokens = divRay(daiTokens, spot);
                        const wethTokens = (await liquidations.collateral(user2, { from: owner })).toString();
    
                        await weth.deposit({ from: buyer, value: liquidatorWethTokens });
                        await weth.approve(wethJoin.address, liquidatorWethTokens, { from: buyer });
                        await wethJoin.join(buyer, liquidatorWethTokens, { from: buyer });
                        await vat.frob(WETH, buyer, buyer, buyer, liquidatorWethTokens, liquidatorDaiDebt, { from: buyer });
                        await daiJoin.exit(buyer, daiTokens, { from: buyer });
    
                        await dai.approve(treasury.address, divRay(daiTokens, toRay(2)), { from: buyer });
                        await liquidations.buy(buyer, user2, divRay(daiTokens, toRay(2)), { from: buyer });
    
                        assert.equal(
                            await liquidations.debt(user2, { from: buyer }),
                            divRay(daiTokens, toRay(2)).toString(),
                            "User debt should have been halved",
                        );
                        assert.equal(
                            await weth.balanceOf(buyer, { from: buyer }),
                            addBN(divRay(wethTokens, toRay(2)), 1).toString(), // divRay should round up
                            "Liquidator should have " + addBN(divRay(wethTokens, toRay(2)), 1) + " weth, instead has " + await weth.balanceOf(buyer, { from: buyer }),
                        );
                    });

                    it("liquidations leaving dust revert", async() => {
                        const daiTokens = (await liquidations.debt(user2, { from: buyer })).toString();
                        // console.log(daiTokens); // 180
                        const liquidatorDaiDebt = divRay(daiTokens, rate2);
                        const liquidatorWethTokens = divRay(daiTokens, spot);
                        // console.log(daiDebt.toString());
                        // wethTokens = 100 ether + 1 wei

                        await weth.deposit({ from: buyer, value: liquidatorWethTokens });
                        await weth.approve(wethJoin.address, liquidatorWethTokens, { from: buyer });
                        await wethJoin.join(buyer, liquidatorWethTokens, { from: buyer });
                        await vat.frob(WETH, buyer, buyer, buyer, liquidatorWethTokens, liquidatorDaiDebt, { from: buyer });
                        await daiJoin.exit(buyer, daiTokens, { from: buyer });

                        await dai.approve(treasury.address, daiTokens, { from: buyer });

                        await expectRevert(
                            liquidations.buy(buyer, user2, subBN(daiTokens, 1000), { from: buyer }),
                            "Liquidations: Below dust",
                        );
                    });
                });

                describe("with completed liquidations", () => {
                    beforeEach(async() => {
                        const daiTokens = (await liquidations.debt(user2, { from: buyer })).toString();
                        // console.log(daiTokens); // 180
                        const liquidatorDaiDebt = divRay(daiTokens, rate2);
                        const liquidatorWethTokens = divRay(daiTokens, spot);
                        // console.log(daiDebt.toString());
                        // wethTokens = 100 ether + 1 wei
    
                        await weth.deposit({ from: buyer, value: liquidatorWethTokens });
                        await weth.approve(wethJoin.address, liquidatorWethTokens, { from: buyer });
                        await wethJoin.join(buyer, liquidatorWethTokens, { from: buyer });
                        await vat.frob(WETH, buyer, buyer, buyer, liquidatorWethTokens, liquidatorDaiDebt, { from: buyer });
                        await daiJoin.exit(buyer, daiTokens, { from: buyer });
    
                        await dai.approve(treasury.address, daiTokens, { from: buyer });
                        await liquidations.buy(buyer, user2, daiTokens, { from: buyer });
                    });
    
                    it("liquidated users can retrieve any remaining collateral", async() => {
                        const wethTokens = (await liquidations.collateral(user2, { from: buyer })).toString();
                        await liquidations.withdraw(user2, user2, wethTokens, { from: user2 });

                        assert.equal(
                            await liquidations.collateral(user2, { from: buyer }),
                            0,
                            "User collateral records should have been erased",
                        );
                        assert.equal(
                            await weth.balanceOf(user2, { from: buyer }),
                            wethTokens,
                            "User should have the remaining weth",
                        );
                    });
                });
            });
        });
    });
});

function bytes32ToString(text) {
    return web3.utils.toAscii(text).replace(/\0/g, '');
}