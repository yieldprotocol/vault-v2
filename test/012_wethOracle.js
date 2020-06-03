const Vat = artifacts.require('Vat');
const WethOracle = artifacts.require('WethOracle');

const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('Vat', async (accounts) =>  {
    const [ owner, user ] = accounts;
    let vat;
    let wethOracle;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    const limits =  toRad(10000);
    const spot  = toRay(1.5);
    const rate  = toRay(1.25);
    const price  = spot;


    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        await vat.file(ilk, spotName, spot, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); // TODO: Why can't we specify `, { from: owner }`?
        await vat.fold(ilk, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        wethOracle = await WethOracle.new(vat.address, { from: owner });
    });

    it("should setup vat", async() => {
        assert(
            (await vat.ilks(ilk)).spot,
            spot.toString(),
            "spot not initialized",
        );
        assert(
            (await vat.ilks(ilk)).rate,
            rate.toString(),
            "rate not initialized",
        );
    });

    it("retrieves weth price as spot", async() => {
        assert.equal(
            await wethOracle.price.call({ from: owner }), // price() is a transaction
            price.toString(),
            "Should be " + price,
        );
    });
});