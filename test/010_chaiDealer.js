const Vat = artifacts.require('Vat');
const Pot = artifacts.require('Pot');
const Treasury = artifacts.require('Treasury');
const YDai = artifacts.require('YDai');
const ERC20 = artifacts.require('TestERC20');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Chai = artifacts.require('Chai');
const ChaiOracle = artifacts.require('ChaiOracle');
const ChaiDealer = artifacts.require('ChaiDealer');

const truffleAssert = require('truffle-assertions');

contract('ChaiDealer', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let pot;
    let treasury;
    let yDai;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let chai;
    let chaiOracle;
    let chaiDealer;
    let maturity;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spot = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    const RAY = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('49')
    const limits =  web3.utils.toBN('10').pow(RAD).toString();
    let daiTokens = web3.utils.toWei("125");
    let chaiTokens = web3.utils.toWei("100");
    const chi  = "1250000000000000000000000000";
    const price  = "800000000000000000000000000";
    // console.log(limits);


    beforeEach(async() => {
        // Set up vat, join and weth
        vat = await Vat.new();
        await vat.rely(vat.address, { from: owner });

        weth = await ERC20.new(0, { from: owner }); 
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

        // Set treasury
        treasury = await Treasury.new(
            dai.address,        // dai
            chai.address,       // chai
            weth.address,       // weth
            daiJoin.address,    // daiJoin
            wethJoin.address,   // wethJoin
            vat.address,        // vat
        );

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(vat.address, pot.address, maturity, "Name", "Symbol");

        // Setup ChaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });

        // Setup ChaiDealer
        chaiDealer = await ChaiDealer.new(
            treasury.address,
            dai.address,
            yDai.address,
            chai.address,
            chaiOracle.address,
            { from: owner },
        );
        await yDai.grantAccess(chaiDealer.address, { from: owner });
        await treasury.grantAccess(chaiDealer.address, { from: owner });

        // Borrow dai
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });
        let wethTokens = web3.utils.toWei("500");
        await weth.mint(owner, wethTokens, { from: owner });
        await weth.approve(wethJoin.address, wethTokens, { from: owner });
        await wethJoin.join(owner, wethTokens, { from: owner });
        await vat.frob(ilk, owner, owner, owner, wethTokens, daiTokens, { from: owner });
        await daiJoin.exit(owner, daiTokens, { from: owner });

        // Set chi to 1.1
        await pot.setChi(chi, { from: owner });

        // Convert to chai
        await dai.approve(chai.address, daiTokens, { from: owner }); 
        await chai.join(owner, daiTokens, { from: owner });
    });

    it("allows user to post chai", async() => {
        assert.equal(
            (await chai.balanceOf(owner)),   
            chaiTokens,
            "ERC20Dealer does not have chai",
        );
        assert.equal(
            (await chai.balanceOf(treasury.address)),   
            0,
            "Treasury has chai",
        );
        assert.equal(
            (await chaiDealer.powerOf.call(owner)),   
            0,
            "Owner has borrowing power",
        );
        
        await chai.approve(chaiDealer.address, chaiTokens, { from: owner }); 
        await chaiDealer.post(owner, chaiTokens, { from: owner }); // Post transfers chai

        assert.equal(
            (await chai.balanceOf(treasury.address)),   
            chaiTokens,
            "Treasury should have chai",
        );
        assert.equal(
            (await chai.balanceOf(owner)),   
            0,
            "Owner should not have chai",
        );
        assert.equal(
            (await chaiDealer.powerOf.call(owner)),   
            daiTokens,
            "Owner should have borrowing power",
        );
    });

    describe("with posted chai", () => {
        beforeEach(async() => {
            await chai.approve(chaiDealer.address, chaiTokens, { from: owner }); 
            await chaiDealer.post(owner, chaiTokens, { from: owner });
        });

        it("allows user to withdraw chai", async() => {
            assert.equal(
                (await chai.balanceOf(treasury.address)),   
                chaiTokens,
                "Treasury does not have chai",
            );
            assert.equal(
                (await chai.balanceOf(owner)),   
                0,
                "Owner has chai",
            );
            assert.equal(
                (await chaiDealer.powerOf.call(owner)),   
                daiTokens,
                "Owner does not have borrowing power",
            );

            await chaiDealer.withdraw(owner, chaiTokens, { from: owner }); // Withdraw transfers chai

            assert.equal(
                (await chai.balanceOf(owner)),   
                chaiTokens,
                "ERC20Dealer should have chai",
            );
            assert.equal(
                (await chai.balanceOf(treasury.address)),   
                0,
                "Treasury should not have chai",
            );
            assert.equal(
                (await chaiDealer.powerOf.call(owner)),   
                0,
                "Owner should not have borrowing power",
            );
        });

        it("allows to borrow yDai", async() => {
            assert.equal(
                (await chaiDealer.powerOf.call(owner)),   
                daiTokens,
                "Owner does not have borrowing power",
            );
            assert.equal(
                (await yDai.balanceOf(owner)),   
                0,
                "Owner has yDai",
            );
            assert.equal(
                (await chaiDealer.debtDai.call(owner)),   
                0,
                "Owner has debt",
            );
    
            await chaiDealer.borrow(owner, daiTokens, { from: owner });

            assert.equal(
                (await yDai.balanceOf(owner)),   
                daiTokens,
                "Owner should have yDai",
            );
            assert.equal(
                (await chaiDealer.debtDai.call(owner)),   
                daiTokens, // Debt is in dai always
                "Owner should have debt",
            );
        });

        describe("with borrowed yDai", () => {
            beforeEach(async() => {
                await chaiDealer.borrow(owner, daiTokens, { from: owner }); // Borrow yDai
            });

            it("allows to repay yDai", async() => {
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    daiTokens,
                    "Owner does not have yDai",
                );
                assert.equal(
                    (await chaiDealer.debtDai.call(owner)),   
                    daiTokens,
                    "Owner does not have debt",
                );

                await yDai.approve(chaiDealer.address, daiTokens, { from: owner });
                await chaiDealer.restore(owner, daiTokens, { from: owner }); // Repay is in yDai
    
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    0,
                    "Owner should not have yDai",
                );
                assert.equal(
                    (await chaiDealer.debtDai.call(owner)),   
                    0,
                    "Owner should not have debt",
                );
            });
        });
    });
});