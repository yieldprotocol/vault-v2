const Vat = artifacts.require('Vat');
const WethOracle = artifacts.require('WethOracle');

const { toWad, toRay, toRad } = require('./shared/utils');

contract('Vat', async (accounts) =>  {
    const [ owner, user ] = accounts;
    let vat;
    let wethOracle;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    const limits =  10000;
    const spot  = 1.5;
    const rate  = 1.25;
    const price  = 1.2; // spot / rate


    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        await vat.file(ilk, spotName, toRay(spot), { from: owner });
        await vat.file(ilk, linel, toRad(limits), { from: owner });
        await vat.file(Line, toRad(limits)); // TODO: Why can't we specify `, { from: owner }`?

        await vat.fold(ilk, vat.address, toRay(rate - 1), { from: owner }); // 1 + 0.25

        wethOracle = await WethOracle.new(vat.address, { from: owner });
    });

    it("should setup vat", async() => {
        assert(
            (await vat.ilks(ilk)).spot,
            toRay(spot).toString(),
            "spot not initialized",
        );
        assert(
            (await vat.ilks(ilk)).rate,
            toRay(rate).toString(),
            "rate not initialized",
        );
    });

    it("retrieves weth price as rate / spot", async() => {
        assert.equal(
            await wethOracle.price.call({ from: owner }), // price() is a transaction
            toRay(price).toString(),
            "Should be " + toRay(price),
        );
    });
});