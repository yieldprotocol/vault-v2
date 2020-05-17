const ERC20Dealer = artifacts.require('ERC20Dealer');
const TestERC20 = artifacts.require('TestERC20');
const TestOracle = artifacts.require('TestOracle');
const YDai = artifacts.require('YDai');
const Pot = artifacts.require('Pot');
const Vat = artifacts.require('Vat');
const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const { BN } = require('@openzeppelin/test-helpers');

contract('ERC20Dealer', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let pot;
    let yDai;
    let oracle;
    let token;
    let dealer;
    let maturity;
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
    const erc20Tokens = web3.utils.toWei("110");
    const limits =  web3.utils.toBN('10').pow(RAD).toString();
    // console.log(limits);


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

        // Setup Collateral Token
        token = await TestERC20.new(0, { from: owner }); 

        // Setup Oracle
        oracle = await TestOracle.new({ from: owner });
        await oracle.setPrice(price); // Setting price at 1.1

        // Setup ERC20Dealer
        dealer = await ERC20Dealer.new(yDai.address, token.address, oracle.address, { from: owner });
        yDai.grantAccess(dealer.address, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("allows user to post collateral", async() => {
        assert.equal(
            (await token.balanceOf(dealer.address)),   
            0,
            "ERC20Dealer has collateral",
        );
        assert.equal(
            (await dealer.powerOf.call(owner)),   
            0,
            "Owner has borrowing power",
        );
        
        await token.mint(owner, erc20Tokens, { from: owner });
        await token.approve(dealer.address, erc20Tokens, { from: owner }); 
        await dealer.post(owner, erc20Tokens, { from: owner });

        assert.equal(
            (await token.balanceOf(dealer.address)),   
            erc20Tokens,
            "ERC20Dealer should have collateral",
        );
        assert.equal(
            (await dealer.powerOf.call(owner)),   
            daiTokens,
            "Owner should have borrowing power",
        );
    });

    describe("with posted collateral", () => {
        beforeEach(async() => {
            await token.mint(owner, erc20Tokens, { from: owner });
            await token.approve(dealer.address, erc20Tokens, { from: owner }); 
            await dealer.post(owner, erc20Tokens, { from: owner });
        });

        it("allows user to withdraw collateral", async() => {
            assert.equal(
                (await token.balanceOf(dealer.address)),   
                erc20Tokens,
                "ERC20Dealer does not have collateral",
            );
            assert.equal(
                (await dealer.powerOf.call(owner)),   
                daiTokens,
                "Owner does not have borrowing power",
            );
            assert.equal(
                (await token.balanceOf(owner)),   
                0,
                "Owner has collateral in hand"
            );
            
            await dealer.withdraw(owner, erc20Tokens, { from: owner });

            assert.equal(
                (await token.balanceOf(owner)),   
                erc20Tokens,
                "Owner should have collateral in hand"
            );
            assert.equal(
                (await token.balanceOf(dealer.address)),   
                0,
                "ERC20Dealer should not have collateral",
            );
            assert.equal(
                (await dealer.powerOf.call(owner)),   
                0,
                "Owner should not have borrowing power",
            );
        });

        it("allows to borrow yDai", async() => {
            assert.equal(
                (await dealer.powerOf.call(owner)),   
                daiTokens,
                "Owner does not have borrowing power",
            );
            assert.equal(
                (await yDai.balanceOf(owner)),   
                0,
                "Owner has yDai",
            );
            assert.equal(
                (await dealer.debtOf.call(owner)),   
                0,
                "Owner has debt",
            );
    
            await dealer.borrow(owner, daiTokens, { from: owner });

            assert.equal(
                (await yDai.balanceOf(owner)),   
                daiTokens,
                "Owner should have yDai",
            );
            assert.equal(
                (await dealer.debtOf.call(owner)),   
                daiTokens,
                "Owner should have debt",
            );
        });

        describe("with borrowed yDai", () => {
            beforeEach(async() => {
                await dealer.borrow(owner, daiTokens, { from: owner });
            });

            it("allows to repay yDai", async() => {
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    daiTokens,
                    "Owner does not have yDai",
                );
                assert.equal(
                    (await dealer.debtOf.call(owner)),   
                    daiTokens,
                    "Owner does not have debt",
                );

                await yDai.approve(dealer.address, daiTokens, { from: owner });
                await dealer.repay(owner, daiTokens, { from: owner });
    
                assert.equal(
                    (await yDai.balanceOf(owner)),   
                    0,
                    "Owner should not have yDai",
                );
                assert.equal(
                    (await dealer.debtOf.call(owner)),   
                    0,
                    "Owner should not have debt",
                );
            });
        });
    });
});