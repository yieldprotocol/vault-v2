const Vat = artifacts.require('Vat');
const Pot = artifacts.require('Pot');
const Chai = artifacts.require('Chai');
const Treasury = artifacts.require('Treasury');
const YDai = artifacts.require('YDai');
const ERC20Dealer = artifacts.require('ERC20Dealer');
const ERC20 = artifacts.require("TestERC20");
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const UniLPOracle = artifacts.require('UniLPOracle');
const Uniswap = artifacts.require('./Uniswap');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { expectRevert } = require('@openzeppelin/test-helpers');

contract('UniLPOracle', async (accounts) =>  {
    let [ owner ] = accounts;
    let vat;
    let pot;
    let chai;
    let treasury;
    let yDai;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
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
    const uniLPTokens = web3.utils.toWei("50");
    const daiTokens = web3.utils.toWei("100");
    const tooMuchDai = web3.utils.toWei("101");
    const price  = "500000000000000000000000000";

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        weth = await ERC20.new(0, { from: owner }); 
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });

        // Setup vat
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

        // Setup uniLPToken Token
        uniLPToken = await ERC20.new(0, { from: owner }); 

        // Setup Oracle
        uniswap = await Uniswap.new();
        // Setup UniLPOracle
        uniLPOracle = await UniLPOracle.new(uniswap.address, { from: owner });

        // Setup ERC20Dealer
        uniLPDealer = await ERC20Dealer.new(
            treasury.address,
            dai.address,
            yDai.address,
            uniLPToken.address,
            uniLPOracle.address,
            { from: owner },
        );
        yDai.grantAccess(uniLPDealer.address, { from: owner });
        await treasury.grantAccess(uniLPDealer.address, { from: owner });
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

        /* const amount = web3.utils.toWei("5");
        const n0 = web3.utils.toBN(supply0);
        const n1 = web3.utils.toBN(supply1);
        const tS = web3.utils.toBN(totalSupply);
        let root = Math.sqrt(n0*n1);
        let term = web3.utils.toBN(root);
        let expectedResult = term.mul(web3.utils.toBN('2'))
            .mul(web3.utils.toBN(RAY))
            .div(tS); */

        // result = (await uniLPOracle.price.call()).toString();
        
        assert.equal(  
            await uniLPOracle.price.call(), 
            price
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
                (await uniLPDealer.powerOf.call(owner)),   
                0,
                "Owner has borrowing power",
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
                (await uniLPDealer.powerOf.call(owner)),   
                daiTokens,
                "Owner should have borrowing power",
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
                    (await uniLPDealer.powerOf.call(owner)),   
                    daiTokens,
                    "Owner does not have borrowing power",
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
                    (await uniLPDealer.powerOf.call(owner)),   
                    0,
                    "Owner should not have borrowing power",
                );
            });

            it("allows to borrow yDai", async() => {
                assert.equal(
                    (await uniLPDealer.powerOf.call(owner)),   
                    daiTokens,
                    "Owner does not have borrowing power",
                );
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    0,
                    "Owner has yDai",
                );
                assert.equal(
                    (await uniLPDealer.debtDai.call(owner)),   
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
                    (await uniLPDealer.debtDai.call(owner)),   
                    daiTokens,
                    "Owner should have debt",
                );
            });

            it("doesn't allow to borrow yDai over the price limit", async() => {
                await expectRevert(
                    uniLPDealer.borrow(owner, tooMuchDai, { from: owner }),
                    "ERC20Dealer: Post more collateral",
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
                        (await uniLPDealer.debtDai.call(owner)),   
                        daiTokens,
                        "Owner does not have debt",
                    );

                    await yDai.approve(uniLPDealer.address, daiTokens, { from: owner });
                    await uniLPDealer.restore(owner, daiTokens, { from: owner });
        
                    assert.equal(
                        (await yDai.balanceOf(owner)),   
                        0,
                        "Owner should not have yDai",
                    );
                    assert.equal(
                        (await uniLPDealer.debtDai.call(owner)),   
                        0,
                        "Owner should not have debt",
                    );
                });
            });
        });
    });
});