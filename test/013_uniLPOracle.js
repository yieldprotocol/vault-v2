const UniLPOracle = artifacts.require('./UniLPOracle');
const Uniswap = artifacts.require('./Uniswap');

contract('UniLPOracle', async (accounts) =>  {
    let [ owner ] = accounts;
    let uniswap;

    const RAY  = "1000000000000000000000000000";

    beforeEach(async() => {
        uniswap = await Uniswap.new();
        // Setup UniLPOracle
        uniLPoracle = await UniLPOracle.new(uniswap.address, { from: owner });
    });

    it("should calculate price", async() => {
        const supply0 = web3.utils.toWei("10");
        const supply1 = web3.utils.toWei("40");
        await uniswap.setReserves(supply0, supply1);

        const totalSupply = web3.utils.toWei("20");
        await uniswap.setTotalSupply(totalSupply);

        const amount = web3.utils.toWei("5");
        const n0 = web3.utils.toBN(supply0);
        const n1 = web3.utils.toBN(supply1);
        const tS = web3.utils.toBN(totalSupply);
        let root = Math.sqrt(n0*n1);
        let term = web3.utils.toBN(root);
        let expectedResult = term.mul(web3.utils.toBN('2'))
            .mul(web3.utils.toBN(RAY))
            .div(tS);

        result = (await uniLPoracle.price.call()).toString();
        
        assert.equal(  
            result, 
            expectedResult
        );
    });
});