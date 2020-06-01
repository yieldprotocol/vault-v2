const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const ChaiOracle = artifacts.require('./ChaiOracle');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad } = require('./shared/utils');

contract('ChaiOracle', async (accounts) =>  {
    let [ owner ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let pot;
    let chaiOracle;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    const limits =  10000;
    const spot  = 1.5;
    const rate  = 1.25;
    const daiDebt = 100;
    const daiTokens = daiDebt * rate;
    const wethTokens = daiDebt * rate / spot;
    const chi = 1.25;
    const price = (1 / chi);

    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        weth = await Weth.new({ from: owner });
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spotName, toRay(spot), { from: owner });
        await vat.file(ilk, linel, toRad(limits), { from: owner });
        await vat.file(Line, toRad(limits)); // TODO: Why can't we specify `, { from: owner }`?
        await vat.fold(ilk, vat.address, toRay(rate - 1), { from: owner }); // 1 + 0.25

        // Permissions
        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.hope(daiJoin.address, { from: owner });

        // Setup pot
        pot = await Pot.new(vat.address);
        await pot.setChi(toRay(chi), { from: owner });
        await vat.rely(pot.address, { from: owner });

        // Setup chaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });
    });

    it("retrieves chai price as 1/pot.chi", async() => {
        assert.equal(
            await chaiOracle.price.call({ from: owner }), // price() is a transaction
            toRay(price).toString(),
            "Price should be " + toRay(price),
        );
    });
});