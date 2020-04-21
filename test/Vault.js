const Vault = artifacts.require('Vault');
const TestERC20 = artifacts.require('TestERC20');
const TestOracle = artifacts.require('TestOracle');
const truffleAssert = require('truffle-assertions');

const supply = web3.utils.toWei("1000");
const user1balance = web3.utils.toWei("100");
const collateralToPost = web3.utils.toWei("20");
const underlyingToLock = web3.utils.toWei("5");
const underlyingPrice = web3.utils.toWei("2");
const collateralRatio = web3.utils.toWei("2");
const tooMuchUnderlying = web3.utils.toWei("6");

contract('Vault', async (accounts) =>    {
    let vault;
    let collateral;
    let oracle;
    const [ owner, user1 ] = accounts;

    beforeEach(async() => {
        collateral = await TestERC20.new(supply, { from: owner });
        await collateral.transfer(user1, user1balance, { from: owner });
        oracle = await TestOracle.new({ from: owner });
        await oracle.set(underlyingPrice, { from: owner });
        vault = await Vault.new(collateral.address, oracle.address, collateralRatio);
    });

    it("collateral can't be retrieved if not available", async() => {
        await truffleAssert.fails(
            vault.retrieve(collateralToPost, { from: user1 }),
            truffleAssert.REVERT,
            "Vault: Unlock more collateral",
        );
    });

    it("collateral can't be locked if not available", async() => {
        await truffleAssert.fails(
            vault.lock(user1, underlyingToLock, { from: owner }),
            truffleAssert.REVERT,
            "Vault: Not enough collateral",
        );
    });

    it("tells how much collateral is needed for a position", async() => {
        assert.equal(
            await vault.collateralNeeded(underlyingToLock, { from: user1 }),
            collateralToPost,
        );
    });

    it("collateral can be posted", async() => {
        await collateral.approve(vault.address, collateralToPost, { from: user1 });
        await vault.post(collateralToPost, { from: user1 });
        assert.equal(
                await vault.balanceOf(user1),
                collateralToPost,
        );
    });

    describe('once collateral is posted', () => {
        beforeEach(async() => {
            await collateral.approve(vault.address, collateralToPost, { from: user1 });
            await vault.post(collateralToPost, { from: user1 });
        });

        it("collateral can be retrieved", async() => {
            await vault.retrieve(collateralToPost, { from: user1 });
            assert.equal(
                    await vault.balanceOf(user1),
                    0,
            );
            assert.equal(
                await collateral.balanceOf(user1),
                user1balance,
            );
        });

        it("collateral can be locked", async() => {
            tx = await vault.lock(user1, underlyingToLock, { from: owner });
            assert.equal(
                tx.logs[0].event,
                "CollateralLocked",
            );
        });

        describe('once collateral is locked', () => {
            beforeEach(async() => {
                await vault.lock(user1, underlyingToLock, { from: owner });
            });

            it("collateral can be unlocked", async() => {
                await vault.lock(user1, 0, { from: owner });
                assert.equal(
                    await vault.unlockedOf(user1),
                    collateralToPost,
                );
            });

            it("it can be known if a position is undercollateralized", async() => {
                assert(await vault.isCollateralized(user1, underlyingToLock));
                await oracle.set(web3.utils.toWei("3"), { from: owner });
                assert((await vault.isCollateralized(user1, underlyingToLock)) == false);
            });
        });
    });

    // TODO: Test mint for failed collateral transfers

    /* it("vault are minted with collateral", async() => {
        await collateral.approve(vault.address, web3.utils.toWei("10"), { from: user1 });
        await vault.mint(user1, web3.utils.toWei("10"), { from: user1 });
        assert.equal(
                await vault.balanceOf(user1),
                web3.utils.toWei("10"),
        );
    });

    describe('once users have vaults', () => {
        beforeEach(async() => {
            await collateral.approve(vault.address, web3.utils.toWei("10"), { from: user1 });
            await vault.mint(user1, web3.utils.toWei("10"), { from: user1 });
        });

        it("vault can't be burned before maturity", async() => {
            await truffleAssert.fails(
                vault.burn(web3.utils.toWei("10"), { from: user1 }),
                truffleAssert.REVERT,
                "Vault: Wait for maturity",
            );
        });

        it("vault can be burned for collateral", async() => {
            helper.advanceTimeAndBlock(1000);
            await vault.burn(web3.utils.toWei("10"), { from: user1 });
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


    it("should issue a new vault", async() => {
        var number = await web3.eth.getBlockNumber();
        var currentTimeStamp = (await web3.eth.getBlock(number)).timestamp;
        var era = currentTimeStamp + SECONDS_IN_DAY;
        let series = await TreasurerInstance.issue.call(era.toString());
        await TreasurerInstance.issue(era.toString());
        let repo = await TreasurerInstance.vaults(series);
        let address = repo.where;
        var vaultInstance = await Vault.at(address);
        assert.equal(await vaultInstance.when(), era, "New vault has incorrect era");
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

    it("should make new vaults", async() => {

        // create another vault series with a 24 hour period until maturity
        var number = await web3.eth.getBlockNumber();
        var currentTimeStamp = (await web3.eth.getBlock(number)).timestamp;
        var series = 1;
        var era = currentTimeStamp + SECONDS_IN_DAY;
        result = await TreasurerInstance.issue(era);

        // set up oracle
        const oracle = await Oracle.new();
        var rate = web3.utils.toWei(".01"); // rate = Dai/ETH
        await OracleMock.givenAnyReturnUint(rate); // should price ETH at $100 * ONE

        // make new vaults
        await TreasurerInstance.make(series, web3.utils.toWei("1"), web3.utils.toWei("1"), {from:accounts[1]});

        // check vault balance
        const token = await TreasurerInstance.vaults.call(series);
        const vaultInstance = await Vault.at(token.where);
        const balance = await vaultInstance.balanceOf(accounts[1]);
        assert.equal(balance.toString(), web3.utils.toWei("1"), "Did not make new vaults");

        //check unlocked collateral, locked collateral
        const repo = await TreasurerInstance.repos(series, accounts[1]);
        assert.equal(repo.locked.toString(), web3.utils.toWei("1"), "Did not lock collateral");
        assert.equal(repo.debt.toString(), web3.utils.toWei("1"), "Did not create debt");
    });

    it("should accept tokens to wipe vault debt", async() => {
        var series = 1;
        var amountToWipe = web3.utils.toWei(".1");

        // set up oracle
        const oracle = await Oracle.new();
        var rate = web3.utils.toWei(".01"); // rate = Dai/ETH
        await OracleMock.givenAnyReturnUint(rate); // should price ETH at $100 * ONE

        // get acess to token
        const token = await TreasurerInstance.vaults.call(series);
        const vaultInstance = await Vault.at(token.where);

        //authorize the wipe
        await vaultInstance.approve(TreasurerInstance.address, amountToWipe, {from:accounts[1]});
        // wipe tokens
        await TreasurerInstance.wipe(series, amountToWipe, web3.utils.toWei(".1"), {from:accounts[1]});

        // check vault balance
        const balance = await vaultInstance.balanceOf(accounts[1]);
        assert.equal(balance.toString(), web3.utils.toWei(".9"), "Did not wipe vaults");

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

        // make new vaults with new account
        // at 100 dai/ETH, and 150% collateral requirement (set at deployment),
        // should refuse to create 101 vaults
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

        // make new vaults with new account
        await TreasurerInstance.make(series, web3.utils.toWei("100"), web3.utils.toWei("1.5"), {from:accounts[2]});

        // transfer tokens to another account
        const token = await TreasurerInstance.vaults.call(series);
        const vaultInstance = await Vault.at(token.where);
        await vaultInstance.transfer(accounts[3], web3.utils.toWei("100"), {from:accounts[2]});

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
