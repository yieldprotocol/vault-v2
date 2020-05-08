const Lender = artifacts.require('./Lender');
const ERC20 = artifacts.require("./TestERC20");
const DaiJoin = artifacts.require('DaiJoin');
const GemJoin = artifacts.require('./GemJoin');
const Vat= artifacts.require('./Vat');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');

contract('Lender', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let lender;
    let dai;
    let weth;
    let daiJoin;
    let wethJoin;
    let vat;
    const ilk = web3.utils.fromAscii("ETH-A")
    const Line = web3.utils.fromAscii("Line")
    const spot = web3.utils.fromAscii("spot")
    const linel = web3.utils.fromAscii("line")

    const RAY  = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('45');
    const supply = web3.utils.toWei("1000");
    const limits =  web3.utils.toBN('10000').mul(web3.utils.toBN('10').pow(RAD)).toString(); // 10000 * 10**45

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
        await vat.file(ilk, spot,    RAY, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?

        lender = await Lender.new(
            dai.address,        // dai
            weth.address,       // weth
            daiJoin.address,    // daiJoin
            wethJoin.address,   // wethJoin
            vat.address,        // vat
        );
        await vat.rely(lender.address, { from: owner }); //?

        await lender.grantAccess(user, { from: owner });
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
        await weth.approve(lender.address, amount, { from: user }); 
        await lender.post(user, amount, { from: user });

        // Test transfer of collateral
        assert.equal(
            (await weth.balanceOf(wethJoin.address)),   
            web3.utils.toWei("500")
        );

        // Test collateral registering via `frob`
        let ink = (await vat.urns(ilk, lender.address)).ink.toString()
        assert.equal(
            ink,   
            amount
        );
    });

    describe("with posted collateral", () => {
        beforeEach(async() => {
            let amount = web3.utils.toWei("500");
            await weth.mint(user, amount, { from: user });
            await weth.approve(lender.address, amount, { from: user }); 
            await lender.post(user, amount, { from: user });
        });

        it("allows user to withdraw collateral", async() => {
            assert.equal(
                (await weth.balanceOf(user)),   
                web3.utils.toWei("0")
            );
            
            let amount = web3.utils.toWei("500");
            await lender.withdraw(user, amount, { from: user });

            // Test transfer of collateral
            assert.equal(
                (await weth.balanceOf(user)),   
                web3.utils.toWei("500")
            );

            // Test collateral registering via `frob`
            let ink = (await vat.urns(ilk, lender.address)).ink.toString()
            assert.equal(
                ink,   
                0
            );
        });

        it("allows to borrow dai", async() => {
            // Test with two different stability rates, if possible.
            // Mock Vat contract needs a `setRate` and an `ilks` functions.
            // Mock Vat contract needs the `frob` function to authorize `daiJoin.exit` transfers through the `dart` parameter.
            let daiBorrowed = web3.utils.toWei("100");
            await lender.borrow(user, daiBorrowed, { from: user });

            let daiBalance = (await dai.balanceOf(user)).toString();
            assert.equal(
                daiBalance,   
                daiBorrowed
            );
            // TODO: assert lender debt = daiBorrowed
        });
    
        describe("with a dai debt towards MakerDAO", () => {
            beforeEach(async() => {
                let daiBorrowed = web3.utils.toWei("100");
                await lender.borrow(user, daiBorrowed, { from: user });
            });

            it("repays dai debt and no more", async() => {
                // Test `normalizedAmount >= normalizedDebt`
                let daiBorrowed = web3.utils.toWei("100");
                await dai.approve(lender.address, daiBorrowed, { from: user });
                await lender.repay(user, daiBorrowed, { from: user });
                let daiBalance = (await dai.balanceOf(user)).toString();
                assert.equal(
                    daiBalance,   
                    0
                );
                // assert lender debt = 0
                assert.equal(
                    (await vat.dai(lender.address)).toString(),   
                    0
                );

                // Test `normalizedAmount < normalizedDebt`
                // Mock Vat contract needs to return `normalizedDebt` with a `urns` function
                // The DaiJoin mock contract needs to have a `join` function that authorizes Vat for incoming dai transfers.
                // The DaiJoin mock contract needs to have a function to return it's dai balance.
                // The Vat mock contract needs to have a frob function that takes `dart` dai from user to DaiJoin
                // Should transfer funds from daiJoin
            });
        });
    });
});