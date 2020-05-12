const Vat = artifacts.require('Vat');
const Pot = artifacts.require('Pot');
const YDai = artifacts.require('YDai');
const ERC20Dealer = artifacts.require('ERC20Dealer');
const TestERC20 = artifacts.require("TestERC20");
const UniLPOracle = artifacts.require('UniLPOracle');
const Uniswap = artifacts.require('./Uniswap');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');

contract('UniLPOracle', async (accounts) =>  {
    let [ owner ] = accounts;
    let vat;
    let pot;
    let yDai;
    let uniLPDealer;
    let uniLPToken;
    let uniLPOracle;
    let uniswap;
    let maturity;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spot = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    let snapshot;
    let snapshotId;
    const RAY  = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('49')
    const limits =  web3.utils.toBN('10').pow(RAD).toString();
    const uniLPTokens = web3.utils.toWei("200");
    const daiTokens = web3.utils.toWei("100");

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        // Setup vat
        await vat.file(ilk, spot,    RAY, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?
        await vat.rely(vat.address, { from: owner });

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });
        // Do we need to set the dsr to something different than one?

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(vat.address, pot.address, maturity, "Name", "Symbol");

        // Setup uniLPToken Token
        uniLPToken = await TestERC20.new(0, { from: owner }); 

        // Setup Oracle
        uniswap = await Uniswap.new();
        // Setup UniLPOracle
        uniLPOracle = await UniLPOracle.new(uniswap.address, { from: owner });

        // Setup ERC20Dealer
        uniLPDealer = await ERC20Dealer.new(yDai.address, uniLPToken.address, uniLPOracle.address, { from: owner });
        yDai.grantAccess(uniLPDealer.address, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("should calculate price", async() => {
        const supply0 = web3.utils.toWei("10");
        const supply1 = web3.utils.toWei("40");
        await uniswap.setReserves(supply0, supply1);

        const totalSupply = web3.utils.toWei("20");
        await uniswap.setTotalSupply(totalSupply);

        const amount = web3.utils.toWei("5");
        const n0 = web3.utils.toBN(supply0);
        const n1 = web3.utils.toBN(supply1);
        const tS = web3.utils.toBN(totalSupply);
        let root = Math.sqrt(n0*n1);
        let term = web3.utils.toBN(root);
        let expectedResult = term.mul(web3.utils.toBN('2'))
            .mul(web3.utils.toBN(RAY))
            .div(tS);

        result = (await uniLPOracle.price.call()).toString();
        
        assert.equal(  
            result, 
            expectedResult
        );
    });

    describe("ERC20Dealer tests", () => {
        beforeEach(async() => {
            const supply0 = web3.utils.toWei("10");
            const supply1 = web3.utils.toWei("40");
            await uniswap.setReserves(supply0, supply1);
    
            const totalSupply = web3.utils.toWei("20");
            await uniswap.setTotalSupply(totalSupply);
        });

        it("allows user to post collateral", async() => {
            assert.equal(
                (await uniswap.totalSupply()),   
                web3.utils.toWei("20"),
                "Uniswap doesn't have supply",
            );
            assert.equal(
                (await uniLPToken.balanceOf(uniLPDealer.address)),   
                web3.utils.toWei("0"),
                "ERC20Dealer has collateral",
            );
            assert.equal(
                (await uniLPDealer.unlockedOf.call(owner)),   
                0,
                "Owner has unlocked collateral",
            );
            
            await uniLPToken.mint(owner, uniLPTokens, { from: owner });
            await uniLPToken.approve(uniLPDealer.address, uniLPTokens, { from: owner }); 
            await uniLPDealer.post(owner, uniLPTokens, { from: owner });

            assert.equal(
                (await uniLPToken.balanceOf(uniLPDealer.address)),   
                uniLPTokens,
                "ERC20Dealer should have collateral",
            );
            assert.equal(
                (await uniLPDealer.unlockedOf.call(owner)),   
                uniLPTokens,
                "Owner should have unlocked collateral",
            );
        });

        describe("with posted collateral", () => {
            beforeEach(async() => {
                await uniLPToken.mint(owner, uniLPTokens, { from: owner });
                await uniLPToken.approve(uniLPDealer.address, uniLPTokens, { from: owner }); 
                await uniLPDealer.post(owner, uniLPTokens, { from: owner });
            });

            it("allows user to withdraw collateral", async() => {
                assert.equal(
                    (await uniLPToken.balanceOf(uniLPDealer.address)),   
                    uniLPTokens,
                    "ERC20Dealer does not have collateral",
                );
                assert.equal(
                    (await uniLPDealer.unlockedOf.call(owner)),   
                    uniLPTokens,
                    "Owner does not have unlocked collateral",
                );
                assert.equal(
                    (await uniLPToken.balanceOf(owner)),   
                    0,
                    "Owner has collateral in hand"
                );
                
                await uniLPDealer.withdraw(owner, uniLPTokens, { from: owner });

                assert.equal(
                    (await uniLPToken.balanceOf(owner)),   
                    uniLPTokens,
                    "Owner should have collateral in hand"
                );
                assert.equal(
                    (await uniLPToken.balanceOf(uniLPDealer.address)),   
                    0,
                    "ERC20Dealer should not have collateral",
                );
                assert.equal(
                    (await uniLPDealer.unlockedOf.call(owner)),   
                    0,
                    "Owner should not have unlocked collateral",
                );
            });

            it("allows to borrow yDai", async() => {
                assert.equal(
                    (await uniLPDealer.unlockedOf.call(owner)),   
                    uniLPTokens,
                    "Owner does not have unlocked collateral",
                );
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    0,
                    "Owner has yDai",
                );
                assert.equal(
                    (await uniLPDealer.debtOf.call(owner)),   
                    0,
                    "Owner has debt",
                );

                await uniLPDealer.borrow(owner, daiTokens, { from: owner });

                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    daiTokens,
                    "Owner should have yDai",
                );
                assert.equal(
                    (await uniLPDealer.debtOf.call(owner)),   
                    daiTokens,
                    "Owner should have debt",
                );
                assert.equal(
                    (await uniLPDealer.unlockedOf.call(owner)),   
                    0,
                    "Owner should not have unlocked collateral",
                );
            });

            describe("with borrowed yDai", () => {
                beforeEach(async() => {
                    await uniLPDealer.borrow(owner, daiTokens, { from: owner });
                });

                it("allows to repay yDai", async() => {
                    assert.equal(
                        (await yDai.balanceOf(owner)),   
                        daiTokens,
                        "Owner does not have yDai",
                    );
                    assert.equal(
                        (await uniLPDealer.debtOf.call(owner)),   
                        daiTokens,
                        "Owner does not have debt",
                    );
                    assert.equal(
                        (await uniLPDealer.unlockedOf.call(owner)),   
                        0,
                        "Owner has unlocked collateral",
                    );

                    await yDai.approve(uniLPDealer.address, daiTokens, { from: owner });
                    await uniLPDealer.repay(owner, daiTokens, { from: owner });
        
                    assert.equal(
                        (await uniLPDealer.unlockedOf.call(owner)),   
                        uniLPTokens,
                        "Owner should have unlocked collateral",
                    );
                    assert.equal(
                        (await yDai.balanceOf(owner)),   
                        0,
                        "Owner should not have yDai",
                    );
                    assert.equal(
                        (await uniLPDealer.debtOf.call(owner)),   
                        0,
                        "Owner should not have debt",
                    );
                });
            });
        });
    });
});