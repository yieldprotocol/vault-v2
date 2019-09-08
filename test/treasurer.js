const Treasurer = artifacts.require('./Treasurer');
const YToken = artifacts.require('./yToken');

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


});
