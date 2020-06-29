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
const { BN, expectRevert } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('Dealer - Chai', async (accounts) =>  {
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
    let chaiOracle;
    let wethOracle;
    let treasury;
    let yDai1;
    let yDai2;
    let dealer;

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
    const chi  = toRay(1.25);
    const daiDebt = toWad(120);
    const daiTokens = mulRay(daiDebt, rate);
    const wethTokens = divRay(daiTokens, spot);
    const chaiTokens = divRay(daiTokens, chi);
    let maturity1;
    let maturity2;

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
        dealer.addSeries(yDai1.address, { from: owner });
        yDai1.grantAccess(dealer.address, { from: owner });
        treasury.grantAccess(yDai1.address, { from: owner });

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
        dealer.addSeries(yDai2.address, { from: owner });
        yDai2.grantAccess(dealer.address, { from: owner });
        treasury.grantAccess(yDai2.address, { from: owner });

        // Tests setup
        await pot.setChi(chi, { from: owner });
        await vat.fold(ilk, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        // Borrow dai
        await weth.deposit({ from: user1, value: wethTokens });
        await weth.approve(wethJoin.address, wethTokens, { from: user1 });
        await wethJoin.join(user1, wethTokens, { from: user1 });
        await vat.frob(ilk, user1, user1, user1, wethTokens, daiDebt, { from: user1 });
        await vat.hope(daiJoin.address, { from: user1 });
        await daiJoin.exit(user1, daiTokens, { from: user1 });

        // Convert to chai
        await dai.approve(chai.address, daiTokens, { from: user1 });
        await chai.join(user1, daiTokens, { from: user1 });
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

    it("allows user to post chai", async() => {
        assert.equal(
            await chai.balanceOf(treasury.address),
            0,
            "Treasury has chai",
        );
        assert.equal(
            await dealer.powerOf.call(CHAI, user1),
            0,
            "Owner has borrowing power",
        );
        
        await chai.approve(dealer.address, chaiTokens, { from: user1 });
        await dealer.post(CHAI, user1, user1, chaiTokens, { from: user1 });

        assert.equal(
            await chai.balanceOf(treasury.address),
            chaiTokens.toString(),
            "Treasury should have chai",
        );
        assert.equal(
            await dealer.powerOf.call(CHAI, user1),
            daiTokens.toString(),
            "Owner should have " + daiTokens + " borrowing power, instead has " + (await dealer.powerOf.call(CHAI, user1)),
        );
    });

    describe("with posted chai", () => {
        beforeEach(async() => {
            await chai.approve(dealer.address, chaiTokens, { from: user1 });
            await dealer.post(CHAI, user1, user1, chaiTokens, { from: user1 });
        });

        it("allows user to withdraw chai", async() => {
            assert.equal(
                await chai.balanceOf(treasury.address),
                chaiTokens.toString(),
                "Treasury does not have chai",
            );
            assert.equal(
                await dealer.powerOf.call(CHAI, user1),
                daiTokens.toString(),
                "Owner does not have borrowing power",
            );
            assert.equal(
                await chai.balanceOf(user1),
                0,
                "Owner has collateral in hand"
            );
            
            await dealer.withdraw(CHAI, user1, user1, chaiTokens, { from: user1 });

            assert.equal(
                await chai.balanceOf(user1),
                chaiTokens.toString(),
                "Owner should have collateral in hand"
            );
            assert.equal(
                await chai.balanceOf(treasury.address),
                0,
                "Treasury should not have chai",
            );
            assert.equal(
                await dealer.powerOf.call(CHAI, user1),
                0,
                "Owner should not have borrowing power",
            );
        });

        it("allows to borrow yDai", async() => {
            assert.equal(
                await dealer.powerOf.call(CHAI, user1),
                daiTokens.toString(),
                "Owner does not have borrowing power",
            );
            assert.equal(
                await yDai1.balanceOf(user1),
                0,
                "Owner has yDai",
            );
            assert.equal(
                await dealer.debtDai.call(CHAI, maturity1, user1),
                0,
                "Owner has debt",
            );
    
            await dealer.borrow(CHAI, maturity1, user1, daiTokens, { from: user1 });

            assert.equal(
                await yDai1.balanceOf(user1),
                daiTokens.toString(),
                "Owner should have yDai",
            );
            assert.equal(
                await dealer.debtDai.call(CHAI, maturity1, user1),
                daiTokens.toString(),
                "Owner should have debt",
            );
        });

        it("doesn't allow to borrow yDai beyond borrowing power", async() => {
            assert.equal(
                await dealer.powerOf.call(CHAI, user1),
                daiTokens.toString(),
                "Owner does not have borrowing power",
            );
            assert.equal(
                await dealer.debtDai.call(CHAI, maturity1, user1),
                0,
                "Owner has debt",
            );
    
            await expectRevert(
                dealer.borrow(CHAI, maturity1, user1, addBN(daiTokens, 1), { from: user1 }),
                "Dealer: Too much debt",
            );
        });

        describe("with borrowed yDai", () => {
            beforeEach(async() => {
                await dealer.borrow(CHAI, maturity1, user1, daiTokens, { from: user1 });
            });

            it("doesn't allow to withdraw and become undercollateralized", async() => {
                assert.equal(
                    await dealer.powerOf.call(CHAI, user1),
                    daiTokens.toString(),
                    "Owner does not have borrowing power",
                );
                assert.equal(
                    await dealer.debtDai.call(CHAI, maturity1, user1),
                    daiTokens.toString(),
                    "Owner does not have debt",
                );

                await expectRevert(
                    dealer.borrow(CHAI, maturity1, user1, chaiTokens, { from: user1 }),
                    "Dealer: Too much debt",
                );
            });

            it("allows to repay yDai", async() => {
                assert.equal(
                    await yDai1.balanceOf(user1),
                    daiTokens.toString(),
                    "Owner does not have yDai",
                );
                assert.equal(
                    await dealer.debtDai.call(CHAI, maturity1, user1),
                    daiTokens.toString(),
                    "Owner does not have debt",
                );

                await yDai1.approve(dealer.address, daiTokens, { from: user1 });
                await dealer.repayYDai(CHAI, maturity1, user1, daiTokens, { from: user1 });
    
                assert.equal(
                    await yDai1.balanceOf(user1),
                    0,
                    "Owner should not have yDai",
                );
                assert.equal(
                    await dealer.debtDai.call(CHAI, maturity1, user1),
                    0,
                    "Owner should not have debt",
                );
            });

            it("allows to repay yDai with dai", async() => {
                // Borrow dai
                await vat.hope(daiJoin.address, { from: user1 });
                await vat.hope(wethJoin.address, { from: user1 });
                let wethTokens = web3.utils.toWei("500");
                await weth.deposit({ from: user1, value: wethTokens });
                await weth.approve(wethJoin.address, wethTokens, { from: user1 });
                await wethJoin.join(user1, wethTokens, { from: user1 });
                await vat.frob(ilk, user1, user1, user1, wethTokens, daiTokens, { from: user1 });
                await daiJoin.exit(user1, daiTokens, { from: user1 });

                assert.equal(
                    await dai.balanceOf(user1),
                    daiTokens.toString(),
                    "Owner does not have dai",
                );
                assert.equal(
                    await dealer.debtDai.call(CHAI, maturity1, user1),
                    daiTokens.toString(),
                    "Owner does not have debt",
                );

                await dai.approve(dealer.address, daiTokens, { from: user1 });
                await dealer.repayDai(CHAI, maturity1, user1, daiTokens, { from: user1 });
    
                assert.equal(
                    await dai.balanceOf(user1),
                    0,
                    "Owner should not have yDai",
                );
                assert.equal(
                    await dealer.debtDai.call(CHAI, maturity1, user1),
                    0,
                    "Owner should not have debt",
                );
            });

            it("when dai is provided in excess for repayment, only the necessary amount is taken", async() => {
                // Mint some yDai the sneaky way
                await yDai1.grantAccess(owner, { from: owner });
                await yDai1.mint(user1, 1, { from: owner }); // 1 extra yDai wei
                const yDaiTokens = addBN(daiTokens, 1); // daiTokens + 1 wei

                assert.equal(
                    await yDai1.balanceOf(user1),
                    yDaiTokens.toString(),
                    "Owner does not have yDai",
                );
                assert.equal(
                    await dealer.debtDai.call(CHAI, maturity1, user1),
                    daiTokens.toString(),
                    "Owner does not have debt",
                );

                await yDai1.approve(dealer.address, yDaiTokens, { from: user1 });
                await dealer.repayYDai(CHAI, maturity1, user1, yDaiTokens, { from: user1 });
    
                assert.equal(
                    await yDai1.balanceOf(user1),
                    1,
                    "Owner should have yDai left",
                );
                assert.equal(
                    await dealer.debtDai.call(CHAI, maturity1, user1),
                    0,
                    "Owner should not have debt",
                );
            });

            // Set rate to 1.5
            const rateIncrease = toRay(0.25);
            const rateDifferential = divRay(addBN(rate, rateIncrease), rate);
            const increasedDebt = mulRay(daiTokens, rateDifferential);
            const debtIncrease = subBN(increasedDebt, daiTokens);

            describe("after maturity, with a rate increase", () => {
                beforeEach(async() => {
                    assert.equal(
                        await yDai1.balanceOf(user1),
                        daiTokens.toString(),
                        "Owner does not have yDai",
                    );
                    assert.equal(
                        await dealer.debtDai.call(CHAI, maturity1, user1),
                        daiTokens.toString(),
                        "Owner does not have debt",
                    );
                    // yDai matures
                    await helper.advanceTime(1000);
                    await helper.advanceBlock();
                    await yDai1.mature();

                    await vat.fold(ilk, vat.address, rateIncrease, { from: owner });
                });

                it("as rate increases after maturity, so does the debt in when measured in dai", async() => {
                    assert.equal(
                        await dealer.debtDai.call(CHAI, maturity1, user1),
                        increasedDebt.toString(),
                        "Owner should have " + increasedDebt + " debt after the rate change, instead has " + (await dealer.debtDai.call(CHAI, maturity1, user1)),
                    );
                });
    
                it("as rate increases after maturity, the debt doesn't in when measured in yDai", async() => {
                    let debt = await dealer.debtDai.call(CHAI, maturity1, user1);
                    assert.equal(
                        await dealer.inYDai.call(maturity1, debt),
                        daiTokens.toString(),
                        "Owner should have " + daiTokens + " debt after the rate change, instead has " + (await dealer.inYDai.call(maturity1, debt)),
                    );
                });

                // TODO: Test that when yDai is provided in excess for repayment, only the necessary amount is taken
    
                it("more yDai is required to repay after maturity as rate increases", async() => {
                    await yDai1.approve(dealer.address, daiTokens, { from: user1 });
                    await dealer.repayYDai(CHAI, maturity1, user1, daiTokens, { from: user1 });
        
                    assert.equal(
                        await yDai1.balanceOf(user1),
                        0,
                        "Owner should not have yDai",
                    );
                    assert.equal(
                        await dealer.debtDai.call(CHAI, maturity1, user1),
                        debtIncrease.toString(),
                        "Owner should have " + debtIncrease + " dai debt, instead has " + (await dealer.debtDai.call(CHAI, maturity1, user1)),
                    );
                });
    
                it("all debt can be repaid after maturity", async() => {
                    // Mint some yDai the sneaky way
                    await yDai1.grantAccess(owner, { from: owner });
                    await yDai1.mint(user1, debtIncrease, { from: owner });
    
                    await yDai1.approve(dealer.address, increasedDebt, { from: user1 });
                    await dealer.repayYDai(CHAI, maturity1, user1, increasedDebt, { from: user1 });
        
                    assert.equal(
                        await yDai1.balanceOf(user1),
                        0,
                        "Owner should not have yDai",
                    );
                    assert.equal(
                        await dealer.debtDai.call(CHAI, maturity1, user1),
                        0,
                        "Owner should have no remaining debt",
                    );
                });
            });
        });
    });
});