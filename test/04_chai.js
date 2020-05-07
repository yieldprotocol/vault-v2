const Chai = artifacts.require('./Chai');
const ERC20 = artifacts.require("./TestERC20");
const DaiJoin = artifacts.require('DaiJoin');
const GemJoin = artifacts.require('./GemJoin');
const Vat= artifacts.require('./Vat');
const Pot= artifacts.require('./Pot');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');

contract('Chai', async (accounts) =>  {
    let [ owner ] = accounts;
    let vat;
    let pot;
    let chai;
    let dai;
    let weth;
    let daiJoin;
    let wethJoin;

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

        dai = await ERC20.new(supply, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spot,    RAY, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
        );
        await vat.rely(chai.address, { from: owner });

        // Borrow dai
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });
        let wethTokens = web3.utils.toWei("500");
        let daiTokens = web3.utils.toWei("100");
        await weth.approve(wethJoin.address, wethTokens, { from: owner });
        await wethJoin.join(owner, wethTokens, { from: owner });
        await vat.frob(ilk, owner, owner, owner, wethTokens, daiTokens, { from: owner });
        await daiJoin.exit(owner, daiTokens, { from: owner });

    });

    it("allows to join dai", async() => {
        assert.equal(
            (await dai.balanceOf(chai.address)),   
            web3.utils.toWei("0")
        );
        
        let amount = web3.utils.toWei("100");
        await dai.approve(chai.address, amount, { from: owner }); 
        await chai.join(owner, amount, { from: owner });

        // Test transfer of chai
        assert.equal(
            (await chai.balanceOf(owner)),   
            web3.utils.toWei("100")
        );        
    });

    describe("with posted collateral", () => {
        beforeEach(async() => {
            let amount = web3.utils.toWei("500");
            await weth.mint(owner, amount, { from: owner });
            await weth.approve(chai.address, amount, { from: owner }); 
            await chai.post(amount, { from: owner });
        });

        it("allows owner to withdraw collateral", async() => {
            assert.equal(
                (await weth.balanceOf(owner)),   
                web3.utils.toWei("0")
            );
            
            let amount = web3.utils.toWei("500");
            await chai.withdraw(amount, { from: owner });

            // Test transfer of collateral
            assert.equal(
                (await weth.balanceOf(owner)),   
                web3.utils.toWei("500")
            );

            // Test collateral registering via `frob`
            let ink = (await vat.urns(ilk, chai.address)).ink.toString()
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
            await chai.borrow(owner, daiBorrowed, { from: owner });

            let daiBalance = (await dai.balanceOf(owner)).toString();
            assert.equal(
                daiBalance,   
                daiBorrowed
            );
            // TODO: assert chai debt = daiBorrowed
        });
    
        describe("with a dai debt towards MakerDAO", () => {
            beforeEach(async() => {
                let daiBorrowed = web3.utils.toWei("100");
                await chai.borrow(owner, daiBorrowed, { from: owner });
            });

            it("repays dai debt and no more", async() => {
                // Test `normalizedAmount >= normalizedDebt`
                let daiBorrowed = web3.utils.toWei("100");
                await dai.approve(chai.address, daiBorrowed, { from: owner });
                await chai.repay(owner, daiBorrowed, { from: owner });
                let daiBalance = (await dai.balanceOf(owner)).toString();
                assert.equal(
                    daiBalance,   
                    0
                );
                // assert chai debt = 0
                assert.equal(
                    (await vat.dai(chai.address)).toString(),   
                    0
                );

                // Test `normalizedAmount < normalizedDebt`
                // Mock Vat contract needs to return `normalizedDebt` with a `urns` function
                // The DaiJoin mock contract needs to have a `join` function that authorizes Vat for incoming dai transfers.
                // The DaiJoin mock contract needs to have a function to return it's dai balance.
                // The Vat mock contract needs to have a frob function that takes `dart` dai from owner to DaiJoin
                // Should transfer funds from daiJoin
            });
        });
    });
});