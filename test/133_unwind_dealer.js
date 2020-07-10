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

contract('Unwind - Dealer', async (accounts) =>  {
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
    const rate  = toRay(1.25);
    const chi = toRay(1.2);
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

    /* it("does not attempt to settle treasury debt until Dss unwind initiated", async() => {
        await expectRevert(
            unwind.settleTreasury({ from: owner }),
            "Unwind: End.sol not caged",
        );
    }); */

    describe("with posted collateral and borrowed yDai", () => {
        beforeEach(async() => {
            // Weth setup
            await weth.deposit({ from: user1, value: wethTokens });
            await weth.approve(treasury.address, wethTokens, { from: user1 });
            await dealer.post(WETH, user1, user1, wethTokens, { from: user1 });

            await weth.deposit({ from: user2, value: wethTokens.add(1) });
            await weth.approve(treasury.address, wethTokens.add(1), { from: user2 });
            await dealer.post(WETH, user2, user2, wethTokens.add(1), { from: user2 });
            await dealer.borrow(WETH, maturity1, user2, user2, daiTokens, { from: user2 });

            await weth.deposit({ from: user3, value: wethTokens.mul(3) });
            await weth.approve(treasury.address, wethTokens.mul(3), { from: user3 });
            await dealer.post(WETH, user3, user3, wethTokens.mul(3), { from: user3 });
            await dealer.borrow(WETH, maturity1, user3, user3, daiTokens, { from: user3 });
            await dealer.borrow(WETH, maturity2, user3, user3, daiTokens, { from: user3 });

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
            await dealer.post(CHAI, user1, user1, chaiTokens, { from: user1 });

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
            await dealer.post(CHAI, user2, user2, moreChai, { from: user2 });
            await dealer.borrow(CHAI, maturity1, user2, user2, daiTokens, { from: user2 });

            // user1 has chaiTokens in dealer and no debt.
            // user2 has chaiTokens * 1.1 in dealer and daiTokens debt.

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
                await dealer.debtYDai(WETH, maturity1, user2),
                yDaiTokens.toString(),
                'User2 should have ' + yDaiTokens.toString() + ' maturity1 weth debt, instead has ' + (await dealer.debtYDai(WETH, maturity1, user2)).toString(),
            );
        });

        it("does not allow to redeem YDai if treasury not settled and cashed", async() => {
            await expectRevert(
                unwind.redeem(maturity1, yDaiTokens, user2, { from: user2 }),
                "Unwind: Not ready",
            );
        });

        it("does not allow to settle users if treasury not settled and cashed", async() => {
            await expectRevert(
                unwind.settle(WETH, user2, { from: user2 }),
                "Unwind: Not ready",
            );
        });

        /* it("does not allow to profit if treasury not settled and cashed", async() => {
            await expectRevert(
                unwind.profit(owner, { from: user2 }),
                "Unwind: Not ready",
            );
        }); */

        describe("with Dss unwind initiated and treasury settled", () => {
            beforeEach(async() => {
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
            });

            it("dealer shuts down", async() => {
                assert.equal(
                    await dealer.live.call(),
                    false,
                    'Dealer should not be live',
                );
            });

            it("does not allow to post, withdraw, borrow or repay assets", async() => {
                await expectRevert(
                    dealer.post(WETH, owner, owner, wethTokens, { from: owner }),
                    "Dealer: Not available during unwind",
                );
                await expectRevert(
                    dealer.withdraw(WETH, owner, owner, wethTokens, { from: owner }),
                    "Dealer: Not available during unwind",
                );
                await expectRevert(
                    dealer.borrow(WETH, maturity1, owner, owner, yDaiTokens, { from: owner }),
                    "Dealer: Not available during unwind",
                );
                await expectRevert(
                    dealer.repayDai(WETH, maturity1, owner, owner, daiTokens, { from: owner }),
                    "Dealer: Not available during unwind",
                );
                await expectRevert(
                    dealer.repayYDai(WETH, maturity1, owner, owner, yDaiTokens, { from: owner }),
                    "Dealer: Not available during unwind",
                );
            });

            /* it("does not allow to profit if there is user debt", async() => {
                await expectRevert(
                    unwind.profit(owner, { from: user2 }),
                    "Unwind: Redeem all yDai",
                );
            }); */

            it("user can redeem YDai", async() => {
                await unwind.redeem(maturity1, yDaiTokens, user2, { from: user2 });

                assert.equal(
                    await weth.balanceOf(user2),
                    fixedWeth.toString(),
                    'User2 should have ' + fixedWeth.toString() + ' weth wei, instead has ' + (await weth.balanceOf(user2)).toString(),
                );
            });

            it("allows user to settle weth surplus", async() => {
                await unwind.settle(WETH, user1, { from: user1 });

                assert.equal(
                    await weth.balanceOf(user1),
                    wethTokens.toString(),
                    'User1 should have ' + wethTokens.toString() + ' weth wei',
                );
            });

            it("users can be forced to settle weth surplus", async() => {
                await unwind.settle(WETH, user1, { from: owner });

                assert.equal(
                    await weth.balanceOf(user1),
                    wethTokens.toString(),
                    'User1 should have ' + wethTokens.toString() + ' weth wei',
                );
            });

            it("allows user to settle chai surplus", async() => {
                await unwind.settle(CHAI, user1, { from: user1 });

                // Remember that chai is converted to weth when withdrawing
                assert.equal(
                    await weth.balanceOf(user1),
                    fixedWeth.toString(),
                    'User1 should have ' + fixedWeth.sub(1).toString() + ' weth wei',
                );
            });

            it("users can be forced to settle chai surplus", async() => {
                await unwind.settle(CHAI, user1, { from: owner });

                // Remember that chai is converted to weth when withdrawing
                assert.equal(
                    await weth.balanceOf(user1),
                    fixedWeth.toString(),
                    'User1 should have ' + fixedWeth.sub(1).toString() + ' weth wei',
                );
            });

            it("allows user to settle weth debt", async() => {
                await unwind.settle(WETH, user2, { from: user2 });

                assert.equal(
                    await dealer.debtYDai(WETH, maturity1, user2),
                    0,
                    'User2 should have no maturity1 weth debt',
                );
                // In the tests the settling nets zero surplus, which we tested above
            });

            it("allows user to settle chai debt", async() => {
                await unwind.settle(CHAI, user2, { from: user2 });

                assert.equal(
                    await dealer.debtYDai(CHAI, maturity1, user2),
                    0,
                    'User2 should have no maturity1 chai debt',
                );
                // In the tests the settling nets zero surplus, which we tested above
            });

            it("allows user to settle mutiple weth positions", async() => {
                await unwind.settle(WETH, user3, { from: user3 });

                assert.equal(
                    await weth.balanceOf(user3),
                    wethTokens.mul(3).sub(fixedWeth.mul(2)).sub(1).toString(), // Each position settled substracts daiTokens * fix from the user collateral 
                    'User1 should have ' + wethTokens.mul(3).sub(fixedWeth.mul(2)).sub(1).toString() + ' weth wei, instead has ' + (await weth.balanceOf(user3)),
                );
                // In the tests the settling nets zero surplus, which we tested above
            });

            /* describe("with all yDai redeemed", () => {
                beforeEach(async() => {
                    await unwind.redeem(maturity1, yDaiTokens.mul(2), user2, { from: user2 });
                    await unwind.redeem(maturity1, yDaiTokens, user3, { from: user3 });
                    await unwind.redeem(maturity2, yDaiTokens, user3, { from: user3 });
                });

                it("allows to extract profit", async() => {
                    const profit = await weth.balanceOf(unwind.address);

                    await unwind.profit(owner, { from: owner });
    
                    assert.equal(
                        (await weth.balanceOf(owner)).toString(),
                        profit,
                        'Owner should have ' + profit + ' weth, instead has ' + (await weth.balanceOf(owner)),
                    );
                });
            }); */
        });
    });
});