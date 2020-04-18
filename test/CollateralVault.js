const CollateralVault = artifacts.require('CollateralVault');
const TestERC20 = artifacts.require('TestERC20');
const truffleAssert = require('truffle-assertions');

const supply = web3.utils.toWei("1000");

contract('CollateralVault', async (accounts) =>    {
    let collateralVault;
    let collateral;
    let maturity;
    const [ owner, user1 ] = accounts;

    beforeEach(async() => {
        collateral = await TestERC20.new(supply, { from: owner });
        await collateral.transfer(user1, web3.utils.toWei("100"), { from: owner });
        collateralVault = await CollateralVault.new();
    });

    it("collateral contracts can be added to the vault", async() => {
        const tx = await collateralVault.acceptCollateral(collateral.address, { from: owner });
        assert.equal(
                tx.logs[0].event,
                "CollateralAccepted",
        );
    });

    // TODO: Test mint for failed collateral transfers

    /* it("collateralVault are minted with collateral", async() => {
        await collateral.approve(collateralVault.address, web3.utils.toWei("10"), { from: user1 });
        await collateralVault.mint(user1, web3.utils.toWei("10"), { from: user1 });
        assert.equal(
                await collateralVault.balanceOf(user1),
                web3.utils.toWei("10"),
        );
    });

    describe('once users have collateralVaults', () => {
        beforeEach(async() => {
            await collateral.approve(collateralVault.address, web3.utils.toWei("10"), { from: user1 });
            await collateralVault.mint(user1, web3.utils.toWei("10"), { from: user1 });
        });

        it("collateralVault can't be burned before maturity", async() => {
            await truffleAssert.fails(
                collateralVault.burn(web3.utils.toWei("10"), { from: user1 }),
                truffleAssert.REVERT,
                "CollateralVault: Wait for maturity",
            );
        });

        it("collateralVault can be burned for collateral", async() => {
            helper.advanceTimeAndBlock(1000);
            await collateralVault.burn(web3.utils.toWei("10"), { from: user1 });
            assert.equal(
                    await collateral.balanceOf(user1),
                    web3.utils.toWei("100"),
            );
        });

        // TODO: Test burn for failed collateral transfers
    }); */


/*        const currentTimeStamp = (await web3.eth.getBlock(number)).timestamp;


        currentTimeStamp = currentTimeStamp - 1;
        await truffleAssert.fails(
            TreasurerInstance.issue(currentTimeStamp),
            truffleAssert.REVERT
        );
        //let series = await TreasurerInstance.issue(currentTimeStamp);
    });


    it("should issue a new collateralVault", async() => {
        var number = await web3.eth.getBlockNumber();
        var currentTimeStamp = (await web3.eth.getBlock(number)).timestamp;
        var era = currentTimeStamp + SECONDS_IN_DAY;
        let series = await TreasurerInstance.issue.call(era.toString());
        await TreasurerInstance.issue(era.toString());
        let repo = await TreasurerInstance.collateralVaults(series);
        let address = repo.where;
        var collateralVaultInstance = await CollateralVault.at(address);
        assert.equal(await collateralVaultInstance.when(), era, "New collateralVault has incorrect era");
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

    it("should make new collateralVaults", async() => {

        // create another collateralVault series with a 24 hour period until maturity
        var number = await web3.eth.getBlockNumber();
        var currentTimeStamp = (await web3.eth.getBlock(number)).timestamp;
        var series = 1;
        var era = currentTimeStamp + SECONDS_IN_DAY;
        result = await TreasurerInstance.issue(era);

        // set up oracle
        const oracle = await Oracle.new();
        var rate = web3.utils.toWei(".01"); // rate = Dai/ETH
        await OracleMock.givenAnyReturnUint(rate); // should price ETH at $100 * ONE

        // make new collateralVaults
        await TreasurerInstance.make(series, web3.utils.toWei("1"), web3.utils.toWei("1"), {from:accounts[1]});

        // check collateralVault balance
        const token = await TreasurerInstance.collateralVaults.call(series);
        const collateralVaultInstance = await CollateralVault.at(token.where);
        const balance = await collateralVaultInstance.balanceOf(accounts[1]);
        assert.equal(balance.toString(), web3.utils.toWei("1"), "Did not make new collateralVaults");

        //check unlocked collateral, locked collateral
        const repo = await TreasurerInstance.repos(series, accounts[1]);
        assert.equal(repo.locked.toString(), web3.utils.toWei("1"), "Did not lock collateral");
        assert.equal(repo.debt.toString(), web3.utils.toWei("1"), "Did not create debt");
    });

    it("should accept tokens to wipe collateralVault debt", async() => {
        var series = 1;
        var amountToWipe = web3.utils.toWei(".1");

        // set up oracle
        const oracle = await Oracle.new();
        var rate = web3.utils.toWei(".01"); // rate = Dai/ETH
        await OracleMock.givenAnyReturnUint(rate); // should price ETH at $100 * ONE

        // get acess to token
        const token = await TreasurerInstance.collateralVaults.call(series);
        const collateralVaultInstance = await CollateralVault.at(token.where);

        //authorize the wipe
        await collateralVaultInstance.approve(TreasurerInstance.address, amountToWipe, {from:accounts[1]});
        // wipe tokens
        await TreasurerInstance.wipe(series, amountToWipe, web3.utils.toWei(".1"), {from:accounts[1]});

        // check collateralVault balance
        const balance = await collateralVaultInstance.balanceOf(accounts[1]);
        assert.equal(balance.toString(), web3.utils.toWei(".9"), "Did not wipe collateralVaults");

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

        // make new collateralVaults with new account
        // at 100 dai/ETH, and 150% collateral requirement (set at deployment),
        // should refuse to create 101 collateralVaults
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

        // make new collateralVaults with new account
        await TreasurerInstance.make(series, web3.utils.toWei("100"), web3.utils.toWei("1.5"), {from:accounts[2]});

        // transfer tokens to another account
        const token = await TreasurerInstance.collateralVaults.call(series);
        const collateralVaultInstance = await CollateralVault.at(token.where);
        await collateralVaultInstance.transfer(accounts[3], web3.utils.toWei("100"), {from:accounts[2]});

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
