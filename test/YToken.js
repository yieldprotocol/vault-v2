const YToken = artifacts.require('YToken');
const Vault = artifacts.require('Vault');
const TestOracle = artifacts.require('TestOracle');
const TestERC20 = artifacts.require('TestERC20');
const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');

const SECONDS_IN_DAY = 86400;
const supply = web3.utils.toWei("1000");
const collateralToPost = web3.utils.toWei("10");
const underlyingToLock = web3.utils.toWei("5");
const underlyingPrice = web3.utils.toWei("2");

contract('YToken', async (accounts) =>    {
    let yToken;
    let collateral;
    let vault;
    let underlying;
    let maturity;
    const [ owner, user1 ] = accounts;
    const user1collateral = web3.utils.toWei("100");
    const user1underlying = web3.utils.toWei("100");

    beforeEach(async() => {
        underlying = await TestERC20.new(supply, { from: owner });
        await underlying.transfer(user1, user1underlying, { from: owner });
        
        collateral = await TestERC20.new(supply, { from: owner });
        await collateral.transfer(user1, user1collateral, { from: owner });
        const oracle = await TestOracle.new({ from: owner });
        await oracle.set(underlyingPrice, { from: owner });
        vault = await Vault.new(collateral.address, oracle.address);

        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yToken = await YToken.new(underlying.address, vault.address, maturity);
        await vault.transferOwnership(yToken.address);
    });

    it("yToken should be initialized", async() => {
        assert.equal(
                await yToken.maturity.call(),
                maturity,
        );

        assert.equal(
                await yToken.underlying.call(),
                underlying.address,
        );
    });

    it("yToken can't be borrowed without enough collateral", async() => {
        await truffleAssert.fails(
            yToken.borrow(web3.utils.toWei("10"), { from: user1 }),
            truffleAssert.REVERT,
            "Vault: Not enough unlocked",
        );
    });

    it("yToken are minted with underlying", async() => {
        await underlying.approve(yToken.address, web3.utils.toWei("10"), { from: user1 });
        await yToken.mint(web3.utils.toWei("10"), { from: user1 });
        assert.equal(
                await yToken.balanceOf(user1),
                web3.utils.toWei("10"),
        );
    });

    it("yToken are borrowed with collateral", async() => {
        await collateral.approve(vault.address, collateralToPost, { from: user1 });
        await vault.post(collateralToPost, { from: user1 });

        await underlying.approve(yToken.address, underlyingToLock, { from: user1 });
        await yToken.borrow(underlyingToLock, { from: user1 });
        assert.equal(
                await yToken.balanceOf(user1),
                underlyingToLock,
        );
    });

    describe('once users have yTokens', () => {
        beforeEach(async() => {
            await underlying.approve(yToken.address, web3.utils.toWei("10"), { from: user1 });
            await yToken.mint(web3.utils.toWei("10"), { from: user1 });
        });

        it("yToken can't be burned before maturity", async() => {
            await truffleAssert.fails(
                yToken.burn(web3.utils.toWei("10"), { from: user1 }),
                truffleAssert.REVERT,
                "YToken: Wait for maturity",
            );
        });

        it("yToken can be burned for underlying", async() => {
            helper.advanceTimeAndBlock(1000);
            await yToken.burn(web3.utils.toWei("10"), { from: user1 });
            assert.equal(
                    await underlying.balanceOf(user1),
                    user1underlying,
            );
        });

        // TODO: Test burn for failed underlying transfers
    });

    describe('once users have borrowed yTokens', () => {
        beforeEach(async() => {
            await collateral.approve(vault.address, collateralToPost, { from: user1 });
            await vault.post(collateralToPost, { from: user1 });
    
            await underlying.approve(yToken.address, underlyingToLock, { from: user1 });
            await yToken.borrow(underlyingToLock, { from: user1 });
        });

        it("debt can be retrieved", async() => {
            assert.equal(
                await yToken.debtOf(user1),
                underlyingToLock,
            );
        });

        it("yToken can't be repaid before maturity", async() => {
            await truffleAssert.fails(
                yToken.repay(underlyingToLock, { from: user1 }),
                truffleAssert.REVERT,
                "YToken: Wait for maturity",
            );
        });

        it("yToken debt can be repaid", async() => {
            helper.advanceTimeAndBlock(1000);
            await yToken.repay(underlyingToLock, { from: user1 });
            assert.equal(
                await yToken.balanceOf(user1),
                0,
            );
            assert.equal(
                await yToken.debtOf(user1),
                0,
            );
        });
    });

/*        const currentTimeStamp = (await web3.eth.getBlock(number)).timestamp;


        currentTimeStamp = currentTimeStamp - 1;
        await truffleAssert.fails(
            TreasurerInstance.issue(currentTimeStamp),
            truffleAssert.REVERT
        );
        //let series = await TreasurerInstance.issue(currentTimeStamp);
    });


    it("should issue a new yToken", async() => {
        var number = await web3.eth.getBlockNumber();
        var currentTimeStamp = (await web3.eth.getBlock(number)).timestamp;
        var era = currentTimeStamp + SECONDS_IN_DAY;
        let series = await TreasurerInstance.issue.call(era.toString());
        await TreasurerInstance.issue(era.toString());
        let repo = await TreasurerInstance.yTokens(series);
        let address = repo.where;
        var yTokenInstance = await YToken.at(address);
        assert.equal(await yTokenInstance.when(), era, "New yToken has incorrect era");
    });

    it("should accept collateral", async() => {
        await TreasurerInstance.join({from:accounts[1], value:web3.utils.toWei("1")});
        var result = await TreasurerInstance.unlocked(accounts[1]);
        assert.equal(result.toString(), web3.utils.toWei("1"), "Did not accept collateral");
    });

    it("should return collateral", async() => {
        await TreasurerInstance.join({from:accounts[1], value:web3.utils.toWei("1")});
        var balance_before = await web3.eth.getBalance(accounts[1]);
        await TreasurerInstance.exit(web3.utils.toWei("1"), {from:accounts[1]});
        var balance_after = await web3.eth.getBalance(accounts[1]);
        assert(balance_after > balance_before);
    });

    it("should provide Oracle address", async() => {
        const _address = await TreasurerInstance.oracle()
        assert.equal(_address, OracleMock.address);
    });

    it("should make new yTokens", async() => {

        // create another yToken series with a 24 hour period until maturity
        var number = await web3.eth.getBlockNumber();
        var currentTimeStamp = (await web3.eth.getBlock(number)).timestamp;
        var series = 1;
        var era = currentTimeStamp + SECONDS_IN_DAY;
        result = await TreasurerInstance.issue(era);

        // set up oracle
        const oracle = await Oracle.new();
        var rate = web3.utils.toWei(".01"); // rate = Dai/ETH
        await OracleMock.givenAnyReturnUint(rate); // should price ETH at $100 * ONE

        // make new yTokens
        await TreasurerInstance.make(series, web3.utils.toWei("1"), web3.utils.toWei("1"), {from:accounts[1]});

        // check yToken balance
        const token = await TreasurerInstance.yTokens.call(series);
        const yTokenInstance = await YToken.at(token.where);
        const balance = await yTokenInstance.balanceOf(accounts[1]);
        assert.equal(balance.toString(), web3.utils.toWei("1"), "Did not make new yTokens");

        //check unlocked collateral, locked collateral
        const repo = await TreasurerInstance.repos(series, accounts[1]);
        assert.equal(repo.locked.toString(), web3.utils.toWei("1"), "Did not lock collateral");
        assert.equal(repo.debt.toString(), web3.utils.toWei("1"), "Did not create debt");
    });

    it("should accept tokens to wipe yToken debt", async() => {
        var series = 1;
        var amountToWipe = web3.utils.toWei(".1");

        // set up oracle
        const oracle = await Oracle.new();
        var rate = web3.utils.toWei(".01"); // rate = Dai/ETH
        await OracleMock.givenAnyReturnUint(rate); // should price ETH at $100 * ONE

        // get acess to token
        const token = await TreasurerInstance.yTokens.call(series);
        const yTokenInstance = await YToken.at(token.where);

        //authorize the wipe
        await yTokenInstance.approve(TreasurerInstance.address, amountToWipe, {from:accounts[1]});
        // wipe tokens
        await TreasurerInstance.wipe(series, amountToWipe, web3.utils.toWei(".1"), {from:accounts[1]});

        // check yToken balance
        const balance = await yTokenInstance.balanceOf(accounts[1]);
        assert.equal(balance.toString(), web3.utils.toWei(".9"), "Did not wipe yTokens");

        //check unlocked collateral, locked collateral
        const repo = await TreasurerInstance.repos(series, accounts[1]);
        assert.equal(repo.locked.toString(), web3.utils.toWei(".9"), "Did not unlock collateral");
        assert.equal(repo.debt.toString(), web3.utils.toWei(".9"), "Did not wipe debg");
    }); */

    /******** No longer relevant, but saved as an example
    it("should not permit re-issuing a series", async() => {
        const TreasurerInstance = await Treasurer.deployed();
        var number = await web3.eth.getBlockNumber();
        var currentTimeStamp = (await web3.eth.getBlock(number)).timestamp;
        // reuse same series number
        var series = 2;
        var era = currentTimeStamp + SECONDS_IN_DAY;
        await truffleAssert.fails(
            TreasurerInstance.issue(era),
            truffleAssert.REVERT
        );
    });
    *****/

    /* it("should refuse to create an undercollateralized repos", async() => {
        var series = 1;

        // set up oracle
        const oracle = await Oracle.new();
        var rate = web3.utils.toWei(".01"); // rate = Dai/ETH
        await OracleMock.givenAnyReturnUint(rate); // should price ETH at $100 * ONE

        // make new yTokens with new account
        // at 100 dai/ETH, and 150% collateral requirement (set at deployment),
        // should refuse to create 101 yTokens
        await TreasurerInstance.join({from:accounts[2], value:web3.utils.toWei("1.5")});
        await truffleAssert.fails(
                TreasurerInstance.make(series, web3.utils.toWei("101"), web3.utils.toWei("1.5"), {from:accounts[2]}),
                truffleAssert.REVERT
        );

    });

    it("should accept liquidations undercollateralized repos", async() => {
        var series = 1;

        // set up oracle
        const oracle = await Oracle.new();
        var rate = web3.utils.toWei(".01"); // rate = Dai/ETH
        await OracleMock.givenAnyReturnUint(rate); // should price ETH at $100 * ONE

        // make new yTokens with new account
        await TreasurerInstance.make(series, web3.utils.toWei("100"), web3.utils.toWei("1.5"), {from:accounts[2]});

        // transfer tokens to another account
        const token = await TreasurerInstance.yTokens.call(series);
        const yTokenInstance = await YToken.at(token.where);
        await yTokenInstance.transfer(accounts[3], web3.utils.toWei("100"), {from:accounts[2]});

        //change rate to make tokens undercollateralized
        rate = web3.utils.toWei(".02"); // rate = Dai/ETH
        await OracleMock.givenAnyReturnUint(rate);
        await truffleAssert.fails(
                TreasurerInstance.wipe(series, web3.utils.toWei("100"), web3.utils.toWei("0"), {from:accounts[2]}),
                truffleAssert.REVERT,
                "treasurer-wipe-insufficient-token-balance"
        );
        var balance_before = await web3.eth.getBalance(accounts[3]);

        // attempt to liquidate
        const result = await TreasurerInstance.liquidate(series, accounts[2], web3.utils.toWei("50"), {from:accounts[3]});

        //check received 1.05
        const tx = await web3.eth.getTransaction(result.tx);
        var balance_after = await web3.eth.getBalance(accounts[3]);
        const total =    Number(balance_after) - Number(balance_before) + result.receipt.gasUsed * tx.gasPrice;
        //try to constrain the test rather than use an inequality (I think the Javascript math is losing precision)
        assert(total > Number(web3.utils.toWei("1.04999")), "liquidation funds not received");
        assert(total < Number(web3.utils.toWei("1.05001")), "liquidation funds not received");

        //check unlocked collateral, locked collateral
        const repo = await TreasurerInstance.repos(series, accounts[2]);
        assert.equal(repo.locked.toString(), web3.utils.toWei(".45"), "Did not unlock collateral");
        assert.equal(repo.debt.toString(), web3.utils.toWei("50"), "Did not wipe debg");

    });

    it("should allow for settlement", async() => {
        var series = 1;
        snapShot = await helper.takeSnapshot();
        snapshotId = snapShot['result'];

        await helper.advanceTime(SECONDS_IN_DAY * 1.5);
        await helper.advanceBlock();
        await TreasurerInstance.settlement(series);
        var rate = (await TreasurerInstance.settled(series)).toString();
        assert.equal(rate, web3.utils.toWei(".02"), "settled rate not set");
        //unwind state
        await helper.revertToSnapshot(snapshotId);
    });

    it("should allow token holder to withdraw face value", async() => {
        var series = 1;
        snapShot = await helper.takeSnapshot();
        snapshotId = snapShot['result'];

        //await helper.advanceTimeAndBlock(SECONDS_IN_DAY * 1.5);
        await helper.advanceTime(SECONDS_IN_DAY * 1.5);
        await helper.advanceBlock();
        await TreasurerInstance.settlement(series);
        var balance_before = await web3.eth.getBalance(accounts[3]);

        const result = await TreasurerInstance.withdraw(series, web3.utils.toWei("25"), {from:accounts[3]});

        var balance_after = await web3.eth.getBalance(accounts[3]);
        const tx = await web3.eth.getTransaction(result.tx);
        const total =    Number(balance_after) - Number(balance_before) + result.receipt.gasUsed * tx.gasPrice;
        assert(total > Number(web3.utils.toWei(".49999")), "withdrawn funds not received");
        assert(total < Number(web3.utils.toWei(".50001")), "withdrawn funds not received");

        //assert.equal(rate, web3.utils.toWei(".02"), "settled rate not set");
        //unwind state
        await helper.revertToSnapshot(snapshotId);
    });

    it("should allow repo holder to close repo and recieve remaining collateral", async() => {
        var series = 1;
        snapShot = await helper.takeSnapshot();
        snapshotId = snapShot['result'];

        //fix margin for account 2 (it is underfunded from wipe test)
        await TreasurerInstance.join({from:accounts[2], value:web3.utils.toWei("1")});
        await TreasurerInstance.make(series, web3.utils.toWei("0"), web3.utils.toWei("1"), {from:accounts[2]}),

        //await helper.advanceTimeAndBlock(SECONDS_IN_DAY * 1.5);
        await helper.advanceTime(SECONDS_IN_DAY * 1.5);
        await helper.advanceBlock();
        await TreasurerInstance.settlement(series);
        var balance_before = await web3.eth.getBalance(accounts[2]);

        //run close
        const result = await TreasurerInstance.close(series, {from:accounts[2]});

        var balance_after = await web3.eth.getBalance(accounts[2]);
        const tx = await web3.eth.getTransaction(result.tx);
        var balance_after = await web3.eth.getBalance(accounts[2]);
        const total =    Number(balance_after) - Number(balance_before) + result.receipt.gasUsed * tx.gasPrice;
        assert(total > Number(web3.utils.toWei(".44999")), "repo funds not received");
        assert(total < Number(web3.utils.toWei(".45001")), "repo funds not received");

        //unwind state
        await helper.revertToSnapshot(snapshotId);

    });
    */
});
