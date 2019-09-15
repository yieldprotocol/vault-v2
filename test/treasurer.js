const Treasurer = artifacts.require('./Treasurer');
const YToken = artifacts.require('./yToken');
const MockContract = artifacts.require("./MockContract")
const Oracle= artifacts.require("./Oracle")
const truffleAssert = require('truffle-assertions');

var OracleMock = null;

contract('Treasurer', async (accounts) =>  {

  before('deploy OracleMock', async() => {
    const TreasurerInstance = await Treasurer.deployed();
    OracleMock = await MockContract.new()
    await TreasurerInstance.set_oracle(OracleMock.address);
  });

  it("should issue a new yToken", async() => {
    const TreasurerInstance = await Treasurer.deployed();

    // Issue yToken with series 1 and era 1
    await TreasurerInstance.issue(1, 1);
    let repo = await TreasurerInstance.yTokens(1);
    let address = repo.where;
    var yTokenInstance = await YToken.at(address);
    assert.equal(await yTokenInstance.era(), 1, "New yToken has incorrect era");
  });

  it("should accept collateral", async() => {
    const TreasurerInstance = await Treasurer.deployed();
    await TreasurerInstance.join({from:accounts[1], value:web3.utils.toWei("1")});
    var result = await TreasurerInstance.gem(accounts[1]);
    assert.equal(result.toString(), web3.utils.toWei("1"), "Did not accept collateral");
  });

  it("should return collateral", async() => {
    const TreasurerInstance = await Treasurer.deployed();
    await TreasurerInstance.join({from:accounts[1], value:web3.utils.toWei("1")});
    var balance_before = await web3.eth.getBalance(accounts[1]);
    await TreasurerInstance.exit(accounts[1], web3.utils.toWei("1"), {from:accounts[1]});
    var balance_after = await web3.eth.getBalance(accounts[1]);
    assert(balance_after > balance_before);
  });

  it("should provide Oracle address", async() => {
    const TreasurerInstance = await Treasurer.deployed();
    const _address = await TreasurerInstance.oracle()
    assert.equal(_address, OracleMock.address);
  });

  it("should make new yTokens", async() => {
    const TreasurerInstance = await Treasurer.deployed();

    // create another yToken series with a 24 hour period until maturity
    var number = await web3.eth.getBlockNumber();
    var currentTimeStamp = (await web3.eth.getBlock(number)).timestamp;
    var series = 2;
    var era = currentTimeStamp + (60*60)*24;
    await TreasurerInstance.issue(series, era);

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
    const TreasurerInstance = await Treasurer.deployed();
    var series = 2;
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
  });

  it("should refuse to create an undercollateralized repos", async() => {
    const TreasurerInstance = await Treasurer.deployed();
    var series = 2;

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

  it("should accept bites of undercollateralized repos", async() => {
    const TreasurerInstance = await Treasurer.deployed();
    var series = 2;

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

    // attempt to bite
    const result = await TreasurerInstance.bite(series, accounts[2], web3.utils.toWei("50"), {from:accounts[3]});

    //check received 1.05
    const tx = await web3.eth.getTransaction(result.tx);
    var balance_after = await web3.eth.getBalance(accounts[3]);
    const total =  Number(balance_after) - Number(balance_before) + result.receipt.gasUsed * tx.gasPrice;
    //try to constrain the test rather than use an inequality (I think the Javascript math is losing precision)
    assert(total > Number(web3.utils.toWei("1.04999")), "bite funds not received");
    assert(total < Number(web3.utils.toWei("1.05001")), "bite funds not received");

    //check unlocked collateral, locked collateral
    const repo = await TreasurerInstance.repos(series, accounts[2]);
    assert.equal(repo.locked.toString(), web3.utils.toWei(".45"), "Did not unlock collateral");
    assert.equal(repo.debt.toString(), web3.utils.toWei("50"), "Did not wipe debg");

  });

});
