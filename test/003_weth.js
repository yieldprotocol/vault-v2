const Weth = artifacts.require('WETH9');

const truffleAssert = require('truffle-assertions');

contract('WETH9', async (accounts) =>  {
    let [ owner ] = accounts;
    let weth;

    beforeEach(async() => {
        weth = await Weth.new(); 
    });

    it("should deposit ether", async() => {
        await weth.deposit({ from: owner, value: 100});
        
        assert.equal(  
            await weth.balanceOf(owner), 
            100,
        );
    });
});