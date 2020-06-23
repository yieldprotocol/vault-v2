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
const { BN, expectRevert, expectEvent } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('Dealer - Splitter', async (accounts) =>  {
    let [ owner, user ] = accounts;
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
    let splitter;

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
    let maturity1;
    let maturity2;

    const gasTokens = 10;

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

        // Setup Splitter
        splitter = await Splitter.new(
            treasury.address,
            dealer.address,
            { from: owner },
        );
        dealer.grantAccess(splitter.address, { from: owner });
        treasury.grantAccess(splitter.address, { from: owner });

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

    it("mints gas tokens when posting", async() => {
        await weth.deposit({ from: owner, value: wethTokens });
        await weth.approve(dealer.address, wethTokens, { from: owner }); 
        await dealer.post(WETH, owner, owner, wethTokens, { from: owner });

        assert.equal(
            await gasToken.balanceOf(dealer.address),
            gasTokens,
            "Dealer should have gasTokens",
        );
    });

    it("takes gas tokens when a new user posts for the first time, if available", async() => {
        await gasToken.mint(gasTokens, { from: owner });
        assert.equal(
            await gasToken.balanceOf(owner),
            gasTokens,
            "User should have gasTokens",
        );
        await gasToken.approve(dealer.address, gasTokens, { from: owner });

        await weth.deposit({ from: owner, value: wethTokens });
        await weth.approve(dealer.address, wethTokens, { from: owner }); 
        await dealer.post(WETH, owner, owner, wethTokens, { from: owner });

        assert.equal(
            await gasToken.balanceOf(owner),
            0,
            "User should have no gasTokens",
        );
        assert.equal(
            await gasToken.balanceOf(dealer.address),
            gasTokens,
            "Dealer should have gasTokens",
        );
    });

    it("does not transfer gas tokens if withdrawal amount and posted collateral are zero", async() => {
        await dealer.withdraw(WETH, owner, owner, 0, { from: owner });

        assert.equal(
            await gasToken.balanceOf(owner),
            0,
            "Owner should not have gasTokens",
        );
    });

    describe("with posted collateral", () => {
        beforeEach(async() => {
            await weth.deposit({ from: owner, value: wethTokens });
            await weth.approve(dealer.address, wethTokens, { from: owner }); 
            await dealer.post(WETH, owner, owner, wethTokens, { from: owner });

            assert.equal(
                await gasToken.balanceOf(dealer.address),
                gasTokens,
                "Dealer should have gasTokens",
            );
        });

        it("mints gas tokens when a new user posts for the first time", async() => {
            await weth.deposit({ from: user, value: wethTokens });
            await weth.approve(dealer.address, wethTokens, { from: user }); 
            await dealer.post(WETH, user, user, wethTokens, { from: user });
    
            assert.equal(
                await gasToken.balanceOf(dealer.address),
                gasTokens * 2,
                "Dealer should have more gasTokens",
            );
        });

        it("does not mint more gas tokens when same user posts again", async() => {
            await weth.deposit({ from: owner, value: wethTokens });
            await weth.approve(dealer.address, wethTokens, { from: owner }); 
            await dealer.post(WETH, owner, owner, wethTokens, { from: owner });
    
            assert.equal(
                await gasToken.balanceOf(dealer.address),
                gasTokens.toString(),
                "Dealer should have gasTokens",
            );
        });

        it("does not transfer gas tokens on partial withdrawals", async() => {
            await dealer.withdraw(WETH, owner, owner, wethTokens.sub(1), { from: owner });

            assert.equal(
                await gasToken.balanceOf(owner),
                0,
                "Owner should not have gasTokens",
            );
        });

        it("transfers gas tokens on withdrawal to zero", async() => {
            await dealer.withdraw(WETH, owner, owner, wethTokens, { from: owner });

            assert.equal(
                await gasToken.balanceOf(owner),
                gasTokens.toString(),
                "Owner should have gasTokens",
            );
        });

        /* it("allows to borrow yDai", async() => {
            await dealer.borrow(maturity1, owner, daiTokens, { from: owner });

            assert.equal(
                await yDai1.balanceOf(owner),
                daiTokens.toString(),
                "Owner should have yDai",
            );
            assert.equal(
                await dealer.debtDai.call(maturity1, owner),
                daiTokens.toString(),
                "Owner should have debt",
            );
        });

        it("doesn't allow to borrow yDai beyond borrowing power", async() => {
            await expectRevert(
                dealer.borrow(maturity1, owner, addBN(daiTokens, 1), { from: owner }), // Borrow 1 wei beyond power
                "Dealer: Too much debt",
            );
        });

        describe("with borrowed yDai", () => {
            beforeEach(async() => {
                await dealer.borrow(maturity1, owner, daiTokens, { from: owner });

                assert.equal(
                    await dealer.powerOf.call(owner),
                    daiTokens.toString(),
                    "Owner does not have borrowing power",
                );
                assert.equal(
                    await dealer.debtDai.call(maturity1, owner),
                    daiTokens.toString(),
                    "Owner does not have debt",
                );
                assert.equal(
                    await yDai1.balanceOf(owner),
                    daiTokens.toString(),
                    "Owner does not have yDai",
                );
                assert.equal(
                    await dealer.debtDai.call(maturity1, owner),
                    daiTokens.toString(),
                    "Owner does not have debt",
                );


            });

            it("allows to borrow from a second series", async() => {
                await weth.deposit({ from: owner, value: wethTokens });
                await weth.approve(dealer.address, wethTokens, { from: owner }); 
                await dealer.post(WETH, owner, owner, wethTokens, { from: owner });
                await dealer.borrow(maturity2, owner, daiTokens, { from: owner });

                assert.equal(
                    await yDai1.balanceOf(owner),
                    daiTokens.toString(),
                    "Owner should have yDai",
                );
                assert.equal(
                    await dealer.debtDai.call(maturity1, owner),
                    daiTokens.toString(),
                    "Owner should have debt for series 1",
                );
                assert.equal(
                    await yDai2.balanceOf(owner),
                    daiTokens.toString(),
                    "Owner should have yDai2",
                );
                assert.equal(
                    await dealer.debtDai.call(maturity2, owner),
                    daiTokens.toString(),
                    "Owner should have debt for series 2",
                );
                assert.equal(
                    await dealer.totalDebtDai.call(owner),
                    addBN(daiTokens, daiTokens).toString(),
                    "Owner should a combined debt",
                );
            });

            describe("with borrowed yDai from two series", () => {
                beforeEach(async() => {
                    await weth.deposit({ from: owner, value: wethTokens });
                    await weth.approve(dealer.address, wethTokens, { from: owner }); 
                    await dealer.post(WETH, owner, owner, wethTokens, { from: owner });
                    await dealer.borrow(maturity2, owner, daiTokens, { from: owner });
                });

                it("doesn't allow to withdraw and become undercollateralized", async() => {
                    await expectRevert(
                        dealer.borrow(maturity1, owner, wethTokens, { from: owner }),
                        "Dealer: Too much debt",
                    );
                });
    
                it("allows to repay yDai", async() => {
                    await yDai1.approve(dealer.address, daiTokens, { from: owner });
                    await dealer.repayYDai(maturity1, owner, daiTokens, { from: owner });
        
                    assert.equal(
                        await yDai1.balanceOf(owner),
                        0,
                        "Owner should not have yDai",
                    );
                    assert.equal(
                        await dealer.debtDai.call(maturity1, owner),
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
                        await dealer.debtDai.call(maturity1, owner),
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
                        await dealer.debtDai.call(maturity1, owner),
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
                        await dealer.debtDai.call(maturity1, owner),
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
                        await dealer.debtDai.call(maturity1, owner),
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
                            await dealer.debtDai.call(maturity1, owner),
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
                            await dealer.debtDai.call(maturity1, owner),
                            increasedDebt.toString(),
                            "Owner should have " + increasedDebt + " debt after the rate change, instead has " + (await dealer.debtDai.call(maturity1, owner)),
                        );
                    });
        
                    it("as rate increases after maturity, the debt doesn't in when measured in yDai", async() => {
                        let debt = await dealer.debtDai.call(maturity1, owner);
                        assert.equal(
                            await dealer.inYDai.call(maturity1, debt),
                            daiTokens.toString(),
                            "Owner should have " + daiTokens + " debt after the rate change, instead has " + (await dealer.inYDai.call(maturity1, debt)),
                        );
                    });
     
                    it("borrowing from two series, dai debt is aggregated", async() => {
                        assert.equal(
                            await dealer.totalDebtDai.call(owner),
                            addBN(increasedDebt, daiTokens).toString(),
                            "Owner should have " + addBN(increasedDebt, daiTokens) + " debt after the rate change, instead has " + (await dealer.totalDebtDai.call(owner)),
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
                            await dealer.debtDai.call(maturity1, owner),
                            debtIncrease.toString(),
                            "Owner should have " + debtIncrease + " dai debt, instead has " + (await dealer.debtDai.call(maturity1, owner)),
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
                            await dealer.debtDai.call(maturity1, owner),
                            0,
                            "Owner should have no remaining debt",
                        );
                    });    
                });    
            });
        }); */
    });
});