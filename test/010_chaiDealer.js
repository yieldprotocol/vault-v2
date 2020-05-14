const Vat = artifacts.require('Vat');
const Pot = artifacts.require('Pot');
const Saver = artifacts.require('Saver');
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
    let saver;
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
    let daiTokens = web3.utils.toWei("110");
    let chaiTokens = web3.utils.toWei("100");
    const chi  = "1100000000000000000000000000";
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

        // Set saver
        saver = await Saver.new(dai.address, chai.address);

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(vat.address, pot.address, maturity, "Name", "Symbol");

        // Setup ChaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });

        // Setup ChaiDealer
        chaiDealer = await ChaiDealer.new(saver.address, yDai.address, chai.address, chaiOracle.address, { from: owner });
        await yDai.grantAccess(chaiDealer.address, { from: owner });
        await saver.grantAccess(chaiDealer.address, { from: owner });

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
            (await chai.balanceOf(saver.address)),   
            0,
            "Saver has chai",
        );
        assert.equal(
            (await chaiDealer.unlockedOf.call(owner)),   
            0,
            "Owner has unlocked collateral",
        );
        
        await chai.approve(chaiDealer.address, chaiTokens, { from: owner }); 
        await chaiDealer.post(owner, chaiTokens, { from: owner }); // Post transfers chai

        assert.equal(
            (await chai.balanceOf(saver.address)),   
            chaiTokens,
            "Saver should have chai",
        );
        assert.equal(
            (await chai.balanceOf(owner)),   
            0,
            "Owner should not have chai",
        );
        assert.equal(
            (await chaiDealer.unlockedOf.call(owner)),   
            chaiTokens,
            "Owner should have unlocked collateral",
        );
    });

    describe("with posted chai", () => {
        beforeEach(async() => {
            await chai.approve(chaiDealer.address, chaiTokens, { from: owner }); 
            await chaiDealer.post(owner, chaiTokens, { from: owner });
        });

        it("allows user to withdraw chai", async() => {
            assert.equal(
                (await chai.balanceOf(saver.address)),   
                chaiTokens,
                "Saver does not have chai",
            );
            assert.equal(
                (await chai.balanceOf(owner)),   
                0,
                "Owner has chai",
            );
            assert.equal(
                (await chaiDealer.unlockedOf.call(owner)),   
                chaiTokens,
                "Owner does not have unlocked collateral",
            );

            await chaiDealer.withdraw(owner, chaiTokens, { from: owner }); // Withdraw transfers chai

            assert.equal(
                (await chai.balanceOf(owner)),   
                chaiTokens,
                "ERC20Dealer should have chai",
            );
            assert.equal(
                (await chai.balanceOf(saver.address)),   
                0,
                "Saver should not have chai",
            );
            assert.equal(
                (await chaiDealer.unlockedOf.call(owner)),   
                0,
                "Owner should have unlocked collateral",
            );
        });

        it("allows to borrow yDai", async() => {
            assert.equal(
                (await chaiDealer.unlockedOf.call(owner)),   
                chaiTokens,
                "Owner does not have unlocked collateral",
            );
            assert.equal(
                (await yDai.balanceOf(owner)),   
                0,
                "Owner has yDai",
            );
            assert.equal(
                (await chaiDealer.debtOf.call(owner)),   
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
                (await chaiDealer.debtOf.call(owner)),   
                daiTokens, // Debt is in dai always
                "Owner should have debt",
            );
            assert.equal(
                (await chaiDealer.unlockedOf.call(owner)),   
                0,
                "Owner should not have unlocked collateral",
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
                    (await chaiDealer.debtOf.call(owner)),   
                    daiTokens,
                    "Owner does not have debt",
                );
                assert.equal(
                    (await chaiDealer.unlockedOf.call(owner)),   
                    0,
                    "Owner has unlocked collateral",
                );

                await yDai.approve(chaiDealer.address, daiTokens, { from: owner });
                await chaiDealer.repay(owner, daiTokens, { from: owner }); // Repay is in yDai
    
                assert.equal(
                    (await chaiDealer.unlockedOf.call(owner)),   
                    chaiTokens,
                    "Owner should have unlocked collateral",
                );
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    0,
                    "Owner should not have yDai",
                );
                assert.equal(
                    (await chaiDealer.debtOf.call(owner)),   
                    0,
                    "Owner should not have debt",
                );
            });
        });
    });
});