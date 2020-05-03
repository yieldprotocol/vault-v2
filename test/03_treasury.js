const Treasury = artifacts.require('./MockTreasury');
const ERC20 = artifacts.require("./TestERC20");
const DaiJoin = artifacts.require('DaiJoin');
const GemJoin = artifacts.require('./GemJoin');
const Pot = artifacts.require('Pot');
const Vat= artifacts.require('./Vat');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');

contract('Treasury', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let weth;
    let dai;
    let wethJoin;
    let daiJoin;
    let pot;
    let treasury;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spot = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")

    const ray  = "1000000000000000000000000000";
    const supply = web3.utils.toWei("1000");
    const rad = web3.utils.toBN('49')
    const limits =  web3.utils.toBN('10').pow(rad).toString();
    const mockAddress = accounts[9];
    // console.log(limits);

    beforeEach(async() => {
        // Set up vat, join and weth
        vat = await Vat.new();
        await vat.rely(vat.address, { from: owner });

        weth = await ERC20.new(supply, { from: owner }); 
        await vat.init(ilk, { from: owner }); // Set ilk rate to 1.0
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spot,    ray, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });

        treasury = await Treasury.new(
            weth.address,       // weth
            dai.address,        // dai
            wethJoin.address,   // wethJoin
            daiJoin.address,    // daiJoin
            vat.address,        // vat
            pot.address         // pot
        );
        await vat.rely(treasury.address, { from: owner }); //?

        await treasury.grantAccess(user, { from: owner });
    });

    it("should fail for failed weth transfers", async() => {
        // Let's check how WETH is implemented, maybe we can remove this one.
    });

    it("allows user to post collateral", async() => {
        assert.equal(
            (await weth.balanceOf(wethJoin.address)),   
            web3.utils.toWei("0")
        );
        
        let amount = web3.utils.toWei("500");
        await weth.mint(user, amount, { from: user });
        await weth.approve(treasury.address, amount, { from: user }); 
        await treasury.post(user, amount, { from: user });

        // Test transfer of collateral
        assert.equal(
            (await weth.balanceOf(wethJoin.address)),   
            web3.utils.toWei("500")
        );

        // Test collateral registering via `frob`
        let ink = (await vat.urns(ilk, treasury.address)).ink.toString()
        assert.equal(
            ink,   
            amount
        );
    });

    describe("with posted collateral", () => {
        beforeEach(async() => {
            let amount = web3.utils.toWei("500");
            await weth.mint(user, amount, { from: user });
            await weth.approve(treasury.address, amount, { from: user }); 
            await treasury.post(user, amount, { from: user });
        });

        it("allows user to withdraw collateral", async() => {
            assert.equal(
                (await weth.balanceOf(user)),   
                web3.utils.toWei("0")
            );
            
            let amount = web3.utils.toWei("500");
            await treasury.withdraw(user, amount, { from: user });

            // Test transfer of collateral
            assert.equal(
                (await weth.balanceOf(user)),   
                web3.utils.toWei("500")
            );

            // Test collateral registering via `frob`
            let ink = (await vat.urns(ilk, treasury.address)).ink.toString()
            assert.equal(
                ink,   
                0
            );
        });

        it("internally allows to borrow dai", async() => {
            // Test with two different stability rates, if possible.
            // Mock Vat contract needs a `setRate` and an `ilks` functions.
            // Mock Vat contract needs the `frob` function to authorize `daiJoin.exit` transfers through the `dart` parameter.
            let daiBorrowed = web3.utils.toWei("100");
            await treasury.borrowDai(user, daiBorrowed, { from: owner });

            let daiBalance = (await dai.balanceOf(user)).toString();
            assert.equal(
                daiBalance,   
                daiBorrowed
            );
            // assert treasury debt = daiBorrowed
        });

        it("borrows dai if there is none in the Pot", async() => {
            let daiBorrowed = web3.utils.toWei("100");
            await treasury.disburse(user, daiBorrowed, { from: user });

            let daiBalance = (await dai.balanceOf(user)).toString();
            assert.equal(
                daiBalance,   
                daiBorrowed
            );
            // assert treasury debt = daiBorrowed
        });
    
        describe("with a dai debt towards MakerDAO", () => {
            beforeEach(async() => {
                let daiBorrowed = web3.utils.toWei("100");
                await treasury.disburse(user, daiBorrowed, { from: user });
            });

            it("internally repays Dai borrowed from the vat", async() => {
                // Test `normalizedAmount >= normalizedDebt`
                let daiBorrowed = web3.utils.toWei("100");
                await dai.transfer(treasury.address, daiBorrowed, { from: user });
                await treasury.repayDai({ from: owner });
                let daiBalance = (await dai.balanceOf(user)).toString();
                assert.equal(
                    daiBalance,   
                    0
                );
                // assert treasury debt = 0

                // Test `normalizedAmount < normalizedDebt`
                // Mock Vat contract needs to return `normalizedDebt` with a `urns` function
                // The DaiJoin mock contract needs to have a `join` function that authorizes Vat for incoming dai transfers.
                // The DaiJoin mock contract needs to have a function to return it's dai balance.
                // The Vat mock contract needs to have a frob function that takes `dart` dai from user to DaiJoin
                // Should transfer funds from daiJoin
            });

            it("repays dai if there is a debt", async() => {
                // Test `normalizedAmount >= normalizedDebt`
                let daiBorrowed = web3.utils.toWei("100");
                await dai.approve(treasury.address, daiBorrowed, { from: user });
                await treasury.repay(user, daiBorrowed, { from: user });
                let daiBalance = (await dai.balanceOf(user)).toString();
                assert.equal(
                    daiBalance,   
                    0
                );
                // assert treasury debt = 0
            });
        });
    });

    describe("repay()", () => {

        it("should fail for failed dai transfers", async() => {
            // Let's check how DAI is implemented, maybe we can remove this one.
        });

        it("should payback debt first", async() => {
            // Dai is transferred from user
            // Test `repayDai()` and `lockDai()` first
            // Test with `normalizedDebt == amount`
            // dai contract can be a standard ERC20
        });

        it("if no debt, should lock Dai in DSR ", async() => {
            // Dai is transferred from user
            // Test with `normalizedDebt == 0 && amount > 0`
            // Test with `normalizedDebt > 0 && amount > normalizedDebt`
        });
    });

    describe("disburse()", () => {

        it("if DSR balance is equal or greater than amount, withdraw from DSR", async() => {
            // Test `_borrowDai()` and `_freeDai` first
            // Test with `balance == amount`
            // Mock Pot contract needs a `setChi()` and `chi()` functions.
            // Mock Pie contract needs a `setPie()` and `pie()` functions.
            // Transfer Dai to the user
        });

        it("if DSR balance is not equal or greater than amount, borrow from Maker", async() => {
            // Test with `balance == 0 && amount > 0`
            // Test with `balance > 0 && amount > balance`
            // Transfer Dai to the user
        });
    });



    describe("_lockDai()", () => {

        it("should transfer all Dai into pot.join", async() => {
            // Test with dai.balanceOf(address(this)) > 0 && pot.chi() != 1
            // The mock Pot contract should inherit from ERC20 and `join` should be a pre-approved `transferFrom`
        });

    });

    describe("_freeDai()", () => {

        it("should request normalized amount Dai from DSR", async() => {
            // Test with amount > 0 && pot.chi() != 1
            // The mock Pot contract should inherit from ERC20 and `exit` should be a `transfer`
        });

    });
});