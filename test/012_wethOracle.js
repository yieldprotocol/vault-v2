const Vat = artifacts.require('Vat');
const WethOracle = artifacts.require('WethOracle');


contract('Vat', async (accounts) =>  {
    const [ owner, user ] = accounts;
    let vat;
    let wethOracle;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    const RAD = web3.utils.toBN('49')
    const limits =  web3.utils.toBN('10').pow(RAD).toString();
    const spot  = "1500000000000000000000000000";
    const rate  = "1250000000000000000000000000";
    const price  = "1200000000000000000000000000"; // spot / rate


    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        await vat.file(ilk, spotName, spot, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); // TODO: Why can't we specify `, { from: owner }`?

        const rateIncrease  = "250000000000000000000000000";
        await vat.fold(ilk, vat.address, rateIncrease, { from: owner }); // 1 + 0.25

        wethOracle = await WethOracle.new(vat.address, { from: owner });
    });

    it("should setup vat", async() => {
        assert(
            (await vat.ilks(ilk)).spot,
            spot,
            "spot not initialized",
        );
        assert(
            (await vat.ilks(ilk)).rate,
            rate,
            "rate not initialized",
        );
    });

    it("retrieves weth price as rate / spot", async() => {
        assert.equal(
            await wethOracle.price.call({ from: owner }), // price() is a transaction
            price,
            "Should be " + price,
        );
    });
});