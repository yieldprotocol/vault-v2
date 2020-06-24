const Weth = artifacts.require('WETH9');

const truffleAssert = require('truffle-assertions');

contract('WETH9', async (accounts) =>  {
    let [ owner ] = accounts;
    let weth;
    const wethTokens = 1;

    beforeEach(async() => {
        weth = await Weth.deployed(); 
    });

    it("should deposit ether", async() => {
        await weth.deposit({ from: owner, value: wethTokens });
        
        assert.equal(  
            await weth.balanceOf(owner), 
            wethTokens,
        );
    });

    it("should withdraw ether", async() => {
        await weth.withdraw(wethTokens, { from: owner });
        
        assert.equal(  
            await weth.balanceOf(owner), 
            0,
        );
    }); 
});