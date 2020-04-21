const TestOracle = artifacts.require('TestOracle');
const truffleAssert = require('truffle-assertions');

const collateralPrice = web3.utils.toWei("0.5");

contract('TestOracle', async (accounts) =>    {
    let oracle;
    const [ owner ] = accounts;

    beforeEach(async() => {
        oracle = await TestOracle.new({ from: owner });
        
    });

    it("price can be set", async() => {
        await oracle.set(collateralPrice, { from: owner });
        assert.equal(
            await oracle.get(),
            collateralPrice,
        );
    });
});
