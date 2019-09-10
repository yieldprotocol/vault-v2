const Treasurer = artifacts.require('./Treasurer');
const YToken = artifacts.require('./yToken');
const MockContract = artifacts.require("./MockContract.sol")

contract('Treasurer', async (accounts) =>  {

  before('deploy TimeContract', async() => {
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

  it("should file Vat address", async() => {
    const TreasurerInstance = await Treasurer.deployed();

    // Instantiate mock and make it return true for any invocation
    const mock = await MockContract.new()
    await TreasurerInstance.oracle(mock.address,  web3.utils.fromAscii("ETH"));

    const address = await TreasurerInstance.vat()
    const ilk     = await TreasurerInstance.ilk()
    assert.equal(address, mock.address);
    assert.equal(web3.utils.toAscii(ilk).replace(/\0.*$/g,''), "ETH");
  });


});
