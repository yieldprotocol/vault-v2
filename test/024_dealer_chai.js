const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const Chai = artifacts.require('Chai');
const ChaiOracle = artifacts.require('ChaiOracle');
const WethOracle = artifacts.require('WethOracle');
const Treasury = artifacts.require('Treasury');
const YDai = artifacts.require('YDai');
const Dealer = artifacts.require('Dealer');

const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN, expectRevert } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('Dealer - Chai', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let pot;
    let chai;
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

        // Permissions
        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.rely(pot.address, { from: owner });
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
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
        );

        // Setup Dealer
        dealer = await Dealer.new(
            treasury.address,
            dai.address,
            chai.address,
            chaiOracle.address,
            CHAI,
            { from: owner },
        );
        treasury.grantAccess(dealer.address, { from: owner });
        
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
        dealer.addSeries(yDai1.address, { from: owner });
        yDai1.grantAccess(dealer.address, { from: owner });
        treasury.grantAccess(yDai1.address, { from: owner });

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
        dealer.addSeries(yDai2.address, { from: owner });
        yDai2.grantAccess(dealer.address, { from: owner });
        treasury.grantAccess(yDai2.address, { from: owner });

        // Borrow dai
        await weth.deposit({ from: owner, value: wethTokens });
        await weth.approve(wethJoin.address, wethTokens, { from: owner });
        await wethJoin.join(owner, wethTokens, { from: owner });
        await vat.frob(ilk, owner, owner, owner, wethTokens, daiDebt, { from: owner });
        await daiJoin.exit(owner, daiTokens, { from: owner });

        // Convert to chai
        await dai.approve(chai.address, daiTokens, { from: owner });
        await chai.join(owner, daiTokens, { from: owner });
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
            await dealer.powerOf.call(owner),
            0,
            "Owner has borrowing power",
        );
        
        await chai.approve(dealer.address, chaiTokens, { from: owner });
        await dealer.post(owner, chaiTokens, { from: owner });

        assert.equal(
            await chai.balanceOf(treasury.address),
            chaiTokens.toString(),
            "Treasury should have chai",
        );
        assert.equal(
            await dealer.powerOf.call(owner),
            daiTokens.toString(),
            "Owner should have " + daiTokens + " borrowing power, instead has " + (await dealer.powerOf.call(owner)),
        );
    });

    describe("with posted chai", () => {
        beforeEach(async() => {
            await chai.approve(dealer.address, chaiTokens, { from: owner });
            await dealer.post(owner, chaiTokens, { from: owner });
        });

        it("allows user to withdraw chai", async() => {
            assert.equal(
                await chai.balanceOf(treasury.address),
                chaiTokens.toString(),
                "Treasury does not have chai",
            );
            assert.equal(
                await dealer.powerOf.call(owner),
                daiTokens.toString(),
                "Owner does not have borrowing power",
            );
            assert.equal(
                await chai.balanceOf(owner),
                0,
                "Owner has collateral in hand"
            );
            
            await dealer.withdraw(owner, chaiTokens, { from: owner });

            assert.equal(
                await chai.balanceOf(owner),
                chaiTokens.toString(),
                "Owner should have collateral in hand"
            );
            assert.equal(
                await chai.balanceOf(treasury.address),
                0,
                "Treasury should not have chai",
            );
            assert.equal(
                await dealer.powerOf.call(owner),
                0,
                "Owner should not have borrowing power",
            );
        });

        it("allows to borrow yDai", async() => {
            assert.equal(
                await dealer.powerOf.call(owner),
                daiTokens.toString(),
                "Owner does not have borrowing power",
            );
            assert.equal(
                await yDai1.balanceOf(owner),
                0,
                "Owner has yDai",
            );
            assert.equal(
                await dealer.debtDai(maturity1, owner),
                0,
                "Owner has debt",
            );
    
            await dealer.borrow(maturity1, owner, daiTokens, { from: owner });

            assert.equal(
                await yDai1.balanceOf(owner),
                daiTokens.toString(),
                "Owner should have yDai",
            );
            assert.equal(
                await dealer.debtDai(maturity1, owner),
                daiTokens.toString(),
                "Owner should have debt",
            );
        });

        it("doesn't allow to borrow yDai beyond borrowing power", async() => {
            assert.equal(
                await dealer.powerOf.call(owner),
                daiTokens.toString(),
                "Owner does not have borrowing power",
            );
            assert.equal(
                await dealer.debtDai(maturity1, owner),
                0,
                "Owner has debt",
            );
    
            await expectRevert(
                dealer.borrow(maturity1, owner, addBN(daiTokens, 1), { from: owner }),
                "Dealer: Too much debt",
            );
        });

        describe("with borrowed yDai", () => {
            beforeEach(async() => {
                await dealer.borrow(maturity1, owner, daiTokens, { from: owner });
            });

            it("doesn't allow to withdraw and become undercollateralized", async() => {
                assert.equal(
                    await dealer.powerOf.call(owner),
                    daiTokens.toString(),
                    "Owner does not have borrowing power",
                );
                assert.equal(
                    await dealer.debtDai(maturity1, owner),
                    daiTokens.toString(),
                    "Owner does not have debt",
                );

                await expectRevert(
                    dealer.borrow(maturity1, owner, chaiTokens, { from: owner }),
                    "Dealer: Too much debt",
                );
            });

            it("allows to repay yDai", async() => {
                assert.equal(
                    await yDai1.balanceOf(owner),
                    daiTokens.toString(),
                    "Owner does not have yDai",
                );
                assert.equal(
                    await dealer.debtDai(maturity1, owner),
                    daiTokens.toString(),
                    "Owner does not have debt",
                );

                await yDai1.approve(dealer.address, daiTokens, { from: owner });
                await dealer.repayYDai(maturity1, owner, daiTokens, { from: owner });
    
                assert.equal(
                    await yDai1.balanceOf(owner),
                    0,
                    "Owner should not have yDai",
                );
                assert.equal(
                    await dealer.debtDai(maturity1, owner),
                    0,
                    "Owner should not have debt",
                );
            });

            it("allows to repay yDai with dai", async() => {
                // Borrow dai
                await vat.hope(daiJoin.address, { from: owner });
                await vat.hope(wethJoin.address, { from: owner });
                let wethTokens = web3.utils.toWei("500");
                await weth.deposit({ from: owner, value: wethTokens });
                await weth.approve(wethJoin.address, wethTokens, { from: owner });
                await wethJoin.join(owner, wethTokens, { from: owner });
                await vat.frob(ilk, owner, owner, owner, wethTokens, daiTokens, { from: owner });
                await daiJoin.exit(owner, daiTokens, { from: owner });

                assert.equal(
                    await dai.balanceOf(owner),
                    daiTokens.toString(),
                    "Owner does not have dai",
                );
                assert.equal(
                    await dealer.debtDai(maturity1, owner),
                    daiTokens.toString(),
                    "Owner does not have debt",
                );

                await dai.approve(dealer.address, daiTokens, { from: owner });
                await dealer.repayDai(maturity1, owner, daiTokens, { from: owner });
    
                assert.equal(
                    await dai.balanceOf(owner),
                    0,
                    "Owner should not have yDai",
                );
                assert.equal(
                    await dealer.debtDai(maturity1, owner),
                    0,
                    "Owner should not have debt",
                );
            });

            it("when dai is provided in excess for repayment, only the necessary amount is taken", async() => {
                // Mint some yDai the sneaky way
                await yDai1.grantAccess(owner, { from: owner });
                await yDai1.mint(owner, 1, { from: owner }); // 1 extra yDai wei
                const yDaiTokens = addBN(daiTokens, 1); // daiTokens + 1 wei

                assert.equal(
                    await yDai1.balanceOf(owner),
                    yDaiTokens.toString(),
                    "Owner does not have yDai",
                );
                assert.equal(
                    await dealer.debtDai(maturity1, owner),
                    daiTokens.toString(),
                    "Owner does not have debt",
                );

                await yDai1.approve(dealer.address, yDaiTokens, { from: owner });
                await dealer.repayYDai(maturity1, owner, yDaiTokens, { from: owner });
    
                assert.equal(
                    await yDai1.balanceOf(owner),
                    1,
                    "Owner should have yDai left",
                );
                assert.equal(
                    await dealer.debtDai(maturity1, owner),
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
                        await yDai1.balanceOf(owner),
                        daiTokens.toString(),
                        "Owner does not have yDai",
                    );
                    assert.equal(
                        await dealer.debtDai(maturity1, owner),
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
                        await dealer.debtDai(maturity1, owner),
                        increasedDebt.toString(),
                        "Owner should have " + increasedDebt + " debt after the rate change, instead has " + (await dealer.debtDai(maturity1, owner)),
                    );
                });
    
                it("as rate increases after maturity, the debt doesn't in when measured in yDai", async() => {
                    let debt = await dealer.debtDai(maturity1, owner);
                    assert.equal(
                        await dealer.inYDai(maturity1, debt),
                        daiTokens.toString(),
                        "Owner should have " + daiTokens + " debt after the rate change, instead has " + (await dealer.inYDai(maturity1, debt)),
                    );
                });

                // TODO: Test that when yDai is provided in excess for repayment, only the necessary amount is taken
    
                it("more yDai is required to repay after maturity as rate increases", async() => {
                    await yDai1.approve(dealer.address, daiTokens, { from: owner });
                    await dealer.repayYDai(maturity1, owner, daiTokens, { from: owner });
        
                    assert.equal(
                        await yDai1.balanceOf(owner),
                        0,
                        "Owner should not have yDai",
                    );
                    assert.equal(
                        await dealer.debtDai(maturity1, owner),
                        debtIncrease.toString(),
                        "Owner should have " + debtIncrease + " dai debt, instead has " + (await dealer.debtDai(maturity1, owner)),
                    );
                });
    
                it("all debt can be repaid after maturity", async() => {
                    // Mint some yDai the sneaky way
                    await yDai1.grantAccess(owner, { from: owner });
                    await yDai1.mint(owner, debtIncrease, { from: owner });
    
                    await yDai1.approve(dealer.address, increasedDebt, { from: owner });
                    await dealer.repayYDai(maturity1, owner, increasedDebt, { from: owner });
        
                    assert.equal(
                        await yDai1.balanceOf(owner),
                        0,
                        "Owner should not have yDai",
                    );
                    assert.equal(
                        await dealer.debtDai(maturity1, owner),
                        0,
                        "Owner should have no remaining debt",
                    );
                });
            });
        });
    });
});