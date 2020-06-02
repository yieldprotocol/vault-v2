const Vat = artifacts.require('Vat');
const Pot = artifacts.require('Pot');
const ERC20 = artifacts.require('TestERC20');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Chai = artifacts.require('Chai');
const Treasury = artifacts.require('Treasury');
const Mint = artifacts.require('Mint');
const TestOracle = artifacts.require('TestOracle');
const ChaiOracle = artifacts.require('ChaiOracle');
const YDai = artifacts.require('YDai');
const Dealer = artifacts.require('Dealer');
const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN } = require('@openzeppelin/test-helpers');
const { expectRevert } = require('@openzeppelin/test-helpers');

contract('Dealer', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let pot;
    let weth;
    let chai;
    let wethJoin;
    let dai;
    let daiJoin;
    let wethOracle;
    let chaiOracle;
    let treasury;
    let yDai;
    let mint;
    let dealer;
    let maturity;
    let WETH = web3.utils.fromAscii("WETH")
    let CHAI = web3.utils.fromAscii("CHAI")
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spot = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    let snapshot;
    let snapshotId;
    const RAY  = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('49')
    const price  = "1100000000000000000000000000";
    const daiTokens = web3.utils.toWei("100");
    const increasedDebt = web3.utils.toWei("150"); // 100 dai * 1.5 rate
    const wethTokens = web3.utils.toWei("110");
    const limits =  web3.utils.toBN('10').pow(RAD).toString();
    // console.log(limits);

    const rateIncrease  = "250000000000000000000000000";
    const moreDai = web3.utils.toWei("125"); //  daiTokens * rate
    const remainingDebt = web3.utils.toWei("25"); //  (daiTokens - (daiTokens / rate)) * rate

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        // Setup vat
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        weth = await ERC20.new(0, { from: owner }); 
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });

        await vat.file(ilk, spot,    RAY, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?
        await vat.rely(vat.address, { from: owner });

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });
        // Do we need to set the dsr to something different than one?

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
        );

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(vat.address, pot.address, maturity, "Name", "Symbol");

        // Setup Oracle
        wethOracle = await TestOracle.new({ from: owner });
        await wethOracle.setPrice(price); // Setting price at 1.1

        // Setup ChaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });

        // Set treasury
        treasury = await Treasury.new(
            dai.address,        // dai
            chai.address,       // chai
            chaiOracle.address, // chaiOracle
            weth.address,       // weth
            daiJoin.address,    // daiJoin
            wethJoin.address,   // wethJoin
            vat.address,        // vat
        );
        await vat.rely(treasury.address, { from: owner }); //?

        // Setup mint
        mint = await Mint.new(
            treasury.address,
            dai.address,
            yDai.address,
            { from: owner },
        );
        await yDai.grantAccess(mint.address, { from: owner });
        await treasury.grantAccess(mint.address, { from: owner });

        // Setup Dealer
        dealer = await Dealer.new(
            treasury.address,
            dai.address,
            yDai.address,
            weth.address,
            wethOracle.address,
            chai.address,
            chaiOracle.address,
            { from: owner },
        );
        treasury.grantAccess(dealer.address, { from: owner });
        yDai.grantAccess(dealer.address, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("allows user to post weth", async() => {
        assert.equal(
            (await vat.urns(ilk, treasury.address)).ink.toString(),   
            0,
            "Treasury has weth in MakerDAO",
        );
        assert.equal(
            (await dealer.powerOf.call(WETH, owner)),   
            0,
            "Owner has borrowing power",
        );
        
        await weth.mint(owner, wethTokens, { from: owner });
        await weth.approve(dealer.address, wethTokens, { from: owner }); 
        await dealer.post(WETH, owner, wethTokens, { from: owner });

        assert.equal(
            (await vat.urns(ilk, treasury.address)).ink.toString(),   
            wethTokens,
            "Treasury should have weth in MakerDAO",
        );
        assert.equal(
            (await dealer.powerOf.call(WETH, owner)),   
            daiTokens,
            "Owner should have borrowing power",
        );
    });

    describe("with posted weth", () => {
        beforeEach(async() => {
            await weth.mint(owner, wethTokens, { from: owner });
            await weth.approve(dealer.address, wethTokens, { from: owner }); 
            await dealer.post(WETH, owner, wethTokens, { from: owner });
        });

        it("allows user to withdraw weth", async() => {
            assert.equal(
                (await vat.urns(ilk, treasury.address)).ink.toString(),   
                wethTokens,
                "Treasury does not have weth in MakerDAO",
            );
            assert.equal(
                (await dealer.powerOf.call(WETH, owner)),   
                daiTokens,
                "Owner does not have borrowing power",
            );
            assert.equal(
                (await weth.balanceOf(owner)),   
                0,
                "Owner has collateral in hand"
            );
            
            await dealer.withdraw(WETH, owner, wethTokens, { from: owner });

            assert.equal(
                (await weth.balanceOf(owner)),   
                wethTokens,
                "Owner should have collateral in hand"
            );
            assert.equal(
                (await vat.urns(ilk, treasury.address)).ink.toString(),   
                0,
                "Treasury should not not have weth in MakerDAO",
            );
            assert.equal(
                (await dealer.powerOf.call(WETH, owner)),   
                0,
                "Owner should not have borrowing power",
            );
        });

        it("allows to borrow yDai", async() => {
            assert.equal(
                (await dealer.powerOf.call(WETH, owner)),   
                daiTokens,
                "Owner does not have borrowing power",
            );
            assert.equal(
                (await yDai.balanceOf(owner)),   
                0,
                "Owner has yDai",
            );
            assert.equal(
                (await dealer.debtDai(WETH, owner)),   
                0,
                "Owner has debt",
            );
    
            await dealer.borrow(WETH, owner, daiTokens, { from: owner });

            assert.equal(
                (await yDai.balanceOf(owner)),   
                daiTokens,
                "Owner should have yDai",
            );
            assert.equal(
                (await dealer.debtDai(WETH, owner)),   
                daiTokens,
                "Owner should have debt",
            );
        });

        it("doesn't allow to borrow yDai beyond borrowing power", async() => {
            assert.equal(
                (await dealer.powerOf.call(WETH, owner)),   
                daiTokens,
                "Owner does not have borrowing power",
            );
            assert.equal(
                (await dealer.debtDai(WETH, owner)),   
                0,
                "Owner has debt",
            );
    
            await expectRevert(
                dealer.borrow(WETH, owner, moreDai, { from: owner }),
                "Dealer: Post more collateral",
            );
        });

        describe("with borrowed yDai", () => {
            beforeEach(async() => {
                await dealer.borrow(WETH, owner, daiTokens, { from: owner });
            });

            it("doesn't allow to withdraw and become undercollateralized", async() => {
                assert.equal(
                    (await dealer.powerOf.call(WETH, owner)),   
                    daiTokens,
                    "Owner does not have borrowing power",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    daiTokens,
                    "Owner does not have debt",
                );

                await expectRevert(
                    dealer.borrow(WETH, owner, wethTokens, { from: owner }),
                    "Dealer: Post more collateral",
                );
            });
            
            it("as rate increases after maturity, so does the debt in when measured in dai", async() => {
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    daiTokens,
                    "Owner should have " + daiTokens + " debt",
                );
                // yDai matures
                await helper.advanceTime(1000);
                await helper.advanceBlock();
                await yDai.mature();

                // Set rate to 1.5
                await vat.fold(ilk, vat.address, "500000000000000000000000000", { from: owner });
                
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    increasedDebt,
                    "Owner should have " + increasedDebt + " debt after the rate change, instead has " + BN(await dealer.debtDai(WETH, owner)),
                );
            });

            it("as rate increases after maturity, the debt doesn't in when measured in yDai", async() => {
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    daiTokens,
                    "Owner should have " + daiTokens + " debt",
                );
                // yDai matures
                await helper.advanceTime(1000);
                await helper.advanceBlock();
                await yDai.mature();

                // Set rate to 1.5
                await vat.fold(ilk, vat.address, "500000000000000000000000000", { from: owner });
                
                let debt = await dealer.debtDai(WETH, owner);
                assert.equal(
                    (await dealer.inYDai(debt)),   
                    daiTokens,
                    "Owner should have " + daiTokens + " debt after the rate change, instead has " + BN(await dealer.inYDai(debt)),
                );
            });

            it("allows to repay yDai", async() => {
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    daiTokens,
                    "Owner does not have yDai",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),
                    daiTokens,
                    "Owner does not have debt",
                );

                await yDai.approve(dealer.address, daiTokens, { from: owner });
                await dealer.repayYDai(WETH, owner, daiTokens, { from: owner });
    
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    0,
                    "Owner should not have yDai",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    0,
                    "Owner should not have debt",
                );
            });

            it("allows to repay yDai with dai", async() => {
                // Borrow dai
                await vat.hope(daiJoin.address, { from: owner });
                await vat.hope(wethJoin.address, { from: owner });
                let wethTokens = web3.utils.toWei("500");
                await weth.mint(owner, wethTokens, { from: owner });
                await weth.approve(wethJoin.address, wethTokens, { from: owner });
                await wethJoin.join(owner, wethTokens, { from: owner });
                await vat.frob(ilk, owner, owner, owner, wethTokens, daiTokens, { from: owner });
                await daiJoin.exit(owner, daiTokens, { from: owner });

                assert.equal(
                    (await dai.balanceOf(owner)),   
                    daiTokens,
                    "Owner does not have dai",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    daiTokens,
                    "Owner does not have debt",
                );

                await dai.approve(dealer.address, daiTokens, { from: owner });
                await dealer.repayDai(WETH, owner, daiTokens, { from: owner });
    
                assert.equal(
                    (await dai.balanceOf(owner)),   
                    0,
                    "Owner should not have yDai",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    0,
                    "Owner should not have debt",
                );
            });

            it("when dai is provided in excess fo repayment, only the necessary amount is taken", async() => {
                // Mint some yDai the sneaky way
                await yDai.grantAccess(owner, { from: owner });
                await yDai.mint(owner, remainingDebt, { from: owner }); // 25 extra yDai

                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    moreDai, // Total 125 dai
                    "Owner does not have yDai",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    daiTokens, // 100 dai
                    "Owner does not have debt",
                );

                await yDai.approve(dealer.address, moreDai, { from: owner });
                await dealer.repayYDai(WETH, owner, moreDai, { from: owner });
    
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    remainingDebt,
                    "Owner should have yDai left",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    0,
                    "Owner should not have debt",
                );
            });

            // TODO: Test that when yDai is provided in excess for repayment, only the necessary amount is taken

            it("more yDai is required to repay after maturity as rate increases", async() => {
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    daiTokens,
                    "Owner does not have yDai",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    daiTokens,
                    "Owner does not have debt",
                );

                // yDai matures
                await helper.advanceTime(1000);
                await helper.advanceBlock();
                await yDai.mature();

                // Rate increase
                await vat.fold(ilk, vat.address, rateIncrease, { from: owner }); // 1 + 0.25

                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    moreDai,
                    "Owner does not have increased debt",
                );

                await yDai.approve(dealer.address, daiTokens, { from: owner });
                await dealer.repayYDai(WETH, owner, daiTokens, { from: owner });
    
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    0,
                    "Owner should not have yDai",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    remainingDebt,
                    "Owner should have " + remainingDebt + " dai debt, instead has " + (await dealer.debtDai(WETH, owner)),
                );
            });

            it("all debt can be repaid after maturity", async() => {
                // Mint some yDai the sneaky way
                await yDai.grantAccess(owner, { from: owner });
                await yDai.mint(owner, remainingDebt, { from: owner });

                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    moreDai,
                    "Owner does not have yDai",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    daiTokens,
                    "Owner does not have debt",
                );

                // yDai matures
                await helper.advanceTime(1000);
                await helper.advanceBlock();
                await yDai.mature();

                // Rate increase
                await vat.fold(ilk, vat.address, rateIncrease, { from: owner }); // 1 + 0.25

                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    moreDai,
                    "Owner does not have increased debt",
                );

                await yDai.approve(dealer.address, moreDai, { from: owner });
                await dealer.repayYDai(WETH, owner, moreDai, { from: owner });
    
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    0,
                    "Owner should not have yDai",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    0,
                    "Owner should have no remaining debt",
                );
            });

            it("allows to move debt to MakerDAO", async() => {
                // Treasury needs to have debt
                await helper.advanceTime(1000);
                await helper.advanceBlock();
                await yDai.mature();
                await yDai.approve(mint.address, daiTokens, { from: owner });
                await mint.redeem(owner, daiTokens, { from: owner });

                const daiDebt = daiTokens;

                assert.equal(
                    (await vat.urns(ilk, treasury.address)).art,   
                    daiDebt,
                    "Treasury does not have " + daiDebt + " debt, instead has " + (await vat.urns(ilk, treasury.address)).art,
                );
                assert.equal(
                    (await vat.urns(ilk, treasury.address)).ink,   
                    wethTokens,
                    "Treasury does not have " + wethTokens + " collateral, instead has " + (await vat.urns(ilk, treasury.address)).ink,
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    daiTokens,
                    "User does not have debt in Dealer",
                );
                assert.equal(
                    (await dealer.posted.call(WETH, owner)),   
                    wethTokens,
                    "User does not have collateral in Dealer",
                );
                assert.equal(
                    (await vat.urns(ilk, owner)).art,   
                    0,
                    "User has debt in MakerDAO",
                );
                assert.equal(
                    (await vat.urns(ilk, owner)).ink,   
                    0,
                    "User has collateral in MakerDAO",
                );
                await vat.hope(treasury.address, { from: owner });
                await dealer.split(owner, owner, { from: owner });
                await vat.nope(treasury.address, { from: owner });
                // TODO: Test with different source and destination accounts
                // TODO: Test with CHAI collateral as well
                // TODO: Test with different rates

                assert.equal(
                    (await vat.urns(ilk, owner)).art,   
                    daiDebt,
                    "User should have debt in MakerDAO",
                );
                assert.equal(
                    (await vat.urns(ilk, owner)).ink,   
                    wethTokens,
                    "User should have collateral in MakerDAO",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    0,
                    "User should not have debt in Dealer",
                );
                assert.equal(
                    (await dealer.posted.call(WETH, owner)),   
                    0,
                    "User should not have collateral in Dealer",
                );
            });

            it("allows to move user debt to MakerDAO beyond system debt", async() => {

                const daiDebt = daiTokens;

                assert.equal(
                    (await vat.urns(ilk, treasury.address)).art,   
                    0,
                    "Treasury has " + daiDebt + " debt, instead of none",
                );
                assert.equal(
                    (await vat.urns(ilk, treasury.address)).ink,   
                    wethTokens,
                    "Treasury does not have " + wethTokens + " collateral, instead has " + (await vat.urns(ilk, treasury.address)).ink,
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    daiTokens,
                    "User does not have debt in Dealer",
                );
                assert.equal(
                    (await dealer.posted.call(WETH, owner)),   
                    wethTokens,
                    "User does not have collateral in Dealer",
                );
                assert.equal(
                    (await vat.urns(ilk, owner)).art,   
                    0,
                    "User has debt in MakerDAO",
                );
                assert.equal(
                    (await vat.urns(ilk, owner)).ink,   
                    0,
                    "User has collateral in MakerDAO",
                );
                assert.equal(
                    (await treasury.savings.call()),   
                    0,
                    "Treasury has savings in dai units"
                );

                await vat.hope(treasury.address, { from: owner });
                await dealer.split(owner, owner, { from: owner });
                await vat.nope(treasury.address, { from: owner });
                // TODO: Test with different source and destination accounts
                // TODO: Test with CHAI collateral as well
                // TODO: Test with different rates

                assert.equal(
                    (await treasury.savings.call()),   
                    daiTokens,
                    "Treasury should report savings in dai units"
                );
                assert.equal(
                    (await vat.urns(ilk, owner)).art,   
                    daiDebt,
                    "User should have debt in MakerDAO",
                );
                assert.equal(
                    (await vat.urns(ilk, owner)).ink,   
                    wethTokens,
                    "User should have collateral in MakerDAO",
                );
                assert.equal(
                    (await dealer.debtDai(WETH, owner)),   
                    0,
                    "User should not have debt in Dealer",
                );
                assert.equal(
                    (await dealer.posted.call(WETH, owner)),   
                    0,
                    "User should not have collateral in Dealer",
                );
            });
        });
    });
});