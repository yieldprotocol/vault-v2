const Migrations = artifacts.require('Migrations');
const Weth = artifacts.require('WETH9');

const truffleAssert = require('truffle-assertions');

contract('WETH9', async (accounts) =>  {
    let [ owner ] = accounts;
    let weth;
    const wethTokens = 1;

    beforeEach(async() => {
        const migrations = await Migrations.deployed();
        weth = await Weth.at(await migrations.contracts(web3.utils.fromAscii("Weth")));
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