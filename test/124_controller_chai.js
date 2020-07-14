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
const EthProxy = artifacts.require('EthProxy');
const Unwind = artifacts.require('Unwind');

const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN, expectRevert } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('Controller - Chai', async (accounts) =>  {
    let [ owner, user1, user2 ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let jug;
    let pot;
    let chai;
    let gasToken;
    let treasury;
    let yDai1;
    let yDai2;
    let controller;

    let WETH = web3.utils.fromAscii("ETH-A");
    let CHAI = web3.utils.fromAscii("CHAI");
    let Line = web3.utils.fromAscii("Line");
    let spotName = web3.utils.fromAscii("spot");
    let linel = web3.utils.fromAscii("line");

    let snapshot;
    let snapshotId;

    const limits = toRad(10000);
    const spot  = toRay(1.5);
    let rate;
    let chi;
    let daiDebt;
    let daiTokens;
    let wethTokens;
    let chaiTokens;

    let maturity1;
    let maturity2;

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

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        rate  = toRay(1.25);
        chi  = toRay(1.25);
        daiDebt = toWad(120);
        daiTokens = mulRay(daiDebt, rate);
        wethTokens = divRay(daiTokens, spot);
        chaiTokens = divRay(daiTokens, chi);

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
        treasury.orchestrate(controller.address, { from: owner });

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
        controller.addSeries(yDai1.address, { from: owner });
        yDai1.orchestrate(controller.address, { from: owner });
        treasury.orchestrate(yDai1.address, { from: owner });

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
        controller.addSeries(yDai2.address, { from: owner });
        yDai2.orchestrate(controller.address, { from: owner });
        treasury.orchestrate(yDai2.address, { from: owner });

        // Tests setup
        await pot.setChi(chi, { from: owner });
        await vat.fold(WETH, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        // Borrow dai
        await getChai(user1, chaiTokens);
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

    it("allows user to post chai", async() => {
        assert.equal(
            await chai.balanceOf(treasury.address),
            0,
            "Treasury has chai",
        );
        assert.equal(
            await controller.powerOf.call(CHAI, user1),
            0,
            "User1 has borrowing power",
        );
        
        await chai.approve(treasury.address, chaiTokens, { from: user1 });
        await controller.post(CHAI, user1, user1, chaiTokens, { from: user1 });

        assert.equal(
            await chai.balanceOf(treasury.address),
            chaiTokens.toString(),
            "Treasury should have chai",
        );
        assert.equal(
            await controller.powerOf.call(CHAI, user1),
            daiTokens.toString(),
            "User1 should have " + daiTokens + " borrowing power, instead has " + (await controller.powerOf.call(CHAI, user1)),
        );
    });

    describe("with posted chai", () => {
        beforeEach(async() => {
            await chai.approve(treasury.address, chaiTokens, { from: user1 });
            await controller.post(CHAI, user1, user1, chaiTokens, { from: user1 });
        });

        it("allows user to withdraw chai", async() => {
            assert.equal(
                await chai.balanceOf(treasury.address),
                chaiTokens.toString(),
                "Treasury does not have chai",
            );
            assert.equal(
                await controller.powerOf.call(CHAI, user1),
                daiTokens.toString(),
                "User1 does not have borrowing power",
            );
            assert.equal(
                await chai.balanceOf(user1),
                0,
                "User1 has collateral in hand"
            );
            
            await controller.withdraw(CHAI, user1, user1, chaiTokens, { from: user1 });

            assert.equal(
                await chai.balanceOf(user1),
                chaiTokens.toString(),
                "User1 should have collateral in hand"
            );
            assert.equal(
                await chai.balanceOf(treasury.address),
                0,
                "Treasury should not have chai",
            );
            assert.equal(
                await controller.powerOf.call(CHAI, user1),
                0,
                "User1 should not have borrowing power",
            );
        });

        it("allows to borrow yDai", async() => {
            assert.equal(
                await controller.powerOf.call(CHAI, user1),
                daiTokens.toString(),
                "User1 does not have borrowing power",
            );
            assert.equal(
                await yDai1.balanceOf(user1),
                0,
                "User1 has yDai",
            );
            assert.equal(
                await controller.debtDai.call(CHAI, maturity1, user1),
                0,
                "User1 has debt",
            );
    
            await controller.borrow(CHAI, maturity1, user1, user1, daiTokens, { from: user1 });

            assert.equal(
                await yDai1.balanceOf(user1),
                daiTokens.toString(),
                "User1 should have yDai",
            );
            assert.equal(
                await controller.debtDai.call(CHAI, maturity1, user1),
                daiTokens.toString(),
                "User1 should have debt",
            );
        });

        it("doesn't allow to borrow yDai beyond borrowing power", async() => {
            assert.equal(
                await controller.powerOf.call(CHAI, user1),
                daiTokens.toString(),
                "User1 does not have borrowing power",
            );
            assert.equal(
                await controller.debtDai.call(CHAI, maturity1, user1),
                0,
                "User1 has debt",
            );
    
            await expectRevert(
                controller.borrow(CHAI, maturity1, user1, user1, addBN(daiTokens, 1), { from: user1 }),
                "Controller: Too much debt",
            );
        });

        describe("with borrowed yDai", () => {
            beforeEach(async() => {
                await controller.borrow(CHAI, maturity1, user1, user1, daiTokens, { from: user1 });
            });

            it("doesn't allow to withdraw and become undercollateralized", async() => {
                assert.equal(
                    await controller.powerOf.call(CHAI, user1),
                    daiTokens.toString(),
                    "User1 does not have borrowing power",
                );
                assert.equal(
                    await controller.debtDai.call(CHAI, maturity1, user1),
                    daiTokens.toString(),
                    "User1 does not have debt",
                );

                await expectRevert(
                    controller.borrow(CHAI, maturity1, user1, user1, chaiTokens, { from: user1 }),
                    "Controller: Too much debt",
                );
            });

            it("allows to repay yDai", async() => {
                assert.equal(
                    await yDai1.balanceOf(user1),
                    daiTokens.toString(),
                    "User1 does not have yDai",
                );
                assert.equal(
                    await controller.debtDai.call(CHAI, maturity1, user1),
                    daiTokens.toString(),
                    "User1 does not have debt",
                );

                await yDai1.approve(treasury.address, daiTokens, { from: user1 });
                await controller.repayYDai(CHAI, maturity1, user1, user1, daiTokens, { from: user1 });
    
                assert.equal(
                    await yDai1.balanceOf(user1),
                    0,
                    "User1 should not have yDai",
                );
                assert.equal(
                    await controller.debtDai.call(CHAI, maturity1, user1),
                    0,
                    "User1 should not have debt",
                );
            });

            it("allows to repay yDai with dai", async() => {
                // Borrow dai
                await getDai(user1, daiTokens);

                assert.equal(
                    await dai.balanceOf(user1),
                    daiTokens.toString(),
                    "User1 does not have dai",
                );
                assert.equal(
                    await controller.debtDai.call(CHAI, maturity1, user1),
                    daiTokens.toString(),
                    "User1 does not have debt",
                );

                await dai.approve(treasury.address, daiTokens, { from: user1 });
                await controller.repayDai(CHAI, maturity1, user1, user1, daiTokens, { from: user1 });
    
                assert.equal(
                    await dai.balanceOf(user1),
                    0,
                    "User1 should not have yDai",
                );
                assert.equal(
                    await controller.debtDai.call(CHAI, maturity1, user1),
                    0,
                    "User1 should not have debt",
                );
            });

            it("when dai is provided in excess for repayment, only the necessary amount is taken", async() => {
                // Mint some yDai the sneaky way
                await yDai1.orchestrate(owner, { from: owner });
                await yDai1.mint(user1, 1, { from: owner }); // 1 extra yDai wei
                const yDaiTokens = addBN(daiTokens, 1); // daiTokens + 1 wei

                assert.equal(
                    await yDai1.balanceOf(user1),
                    yDaiTokens.toString(),
                    "User1 does not have yDai",
                );
                assert.equal(
                    await controller.debtDai.call(CHAI, maturity1, user1),
                    daiTokens.toString(),
                    "User1 does not have debt",
                );

                await yDai1.approve(treasury.address, yDaiTokens, { from: user1 });
                await controller.repayYDai(CHAI, maturity1, user1, user1, yDaiTokens, { from: user1 });
    
                assert.equal(
                    await yDai1.balanceOf(user1),
                    1,
                    "User1 should have yDai left",
                );
                assert.equal(
                    await controller.debtDai.call(CHAI, maturity1, user1),
                    0,
                    "User1 should not have debt",
                );
            });

            let rateIncrease;
            let chiIncrease;
            let chiDifferential;
            let increasedDebt;
            let debtIncrease;

            describe("after maturity, with a chi increase", () => {
                beforeEach(async() => {
                    // Set rate to 1.75
                    rateIncrease = toRay(0.5);
                    rate = rate.add(rateIncrease);
                    // Set chi to 1.5
                    chiIncrease = toRay(0.25);
                    chiDifferential = divRay(addBN(chi, chiIncrease), chi);
                    chi = chi.add(chiIncrease);
                    
                    increasedDebt = mulRay(daiTokens, chiDifferential);
                    debtIncrease = subBN(increasedDebt, daiTokens);

                    assert.equal(
                        await yDai1.balanceOf(user1),
                        daiTokens.toString(),
                        "User1 does not have yDai",
                    );
                    assert.equal(
                        await controller.debtDai.call(CHAI, maturity1, user1),
                        daiTokens.toString(),
                        "User1 does not have debt",
                    );
                    // yDai matures
                    await helper.advanceTime(1000);
                    await helper.advanceBlock();
                    await yDai1.mature();

                    // Increase rate
                    await vat.fold(WETH, vat.address, rateIncrease, { from: owner });
                    // Increase chi
                    await pot.setChi(chi, { from: owner });
                });

                it("as chi increases after maturity, so does the debt in when measured in dai", async() => {
                    assert.equal(
                        await controller.debtDai.call(CHAI, maturity1, user1),
                        increasedDebt.toString(),
                        "User1 should have " + increasedDebt + " debt after the chi change, instead has " + (await controller.debtDai.call(CHAI, maturity1, user1)),
                    );
                });
    
                it("as chi increases after maturity, the debt doesn't in when measured in yDai", async() => {
                    let debt = await controller.debtDai.call(CHAI, maturity1, user1);
                    assert.equal(
                        await controller.inYDai.call(CHAI, maturity1, debt),
                        daiTokens.toString(),
                        "User1 should have " + daiTokens + " debt after the chi change, instead has " + (await controller.inYDai.call(CHAI, maturity1, debt)),
                    );
                });

                // TODO: Test that when yDai is provided in excess for repayment, only the necessary amount is taken
    
                // TODO: Fix whatever makes `getDai` to be Vat/not-safe
                /* it("more Dai is required to repay after maturity as chi increases", async() => {
                    await getDai(user1, daiTokens); // daiTokens is not going to be enough anymore
                    await dai.approve(treasury.address, daiTokens, { from: user1 });
                    await controller.repayDai(CHAI, maturity1, user1, daiTokens, { from: user1 });
        
                    assert.equal(
                        await controller.debtDai.call(CHAI, maturity1, user1),
                        debtIncrease.toString(),
                        "User1 should have " + debtIncrease + " dai debt, instead has " + (await controller.debtDai.call(CHAI, maturity1, user1)),
                    );
                }); */
            });
        });
    });
});