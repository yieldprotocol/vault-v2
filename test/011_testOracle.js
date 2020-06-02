const TestOracle = artifacts.require('TestOracle');
const truffleAssert = require('truffle-assertions');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

const price = toRay(0.5);

contract('TestOracle', async (accounts) =>    {
    let oracle;
    const [ owner ] = accounts;

    beforeEach(async() => {
        oracle = await TestOracle.new({ from: owner });
        
    });

    it("price can be set", async() => {
        await oracle.setPrice(price, { from: owner });
        assert.equal(
            await oracle.price.call(),
            price.toString(),
        );
    });
});
