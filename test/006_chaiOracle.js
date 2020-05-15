const ChaiOracle = artifacts.require('./ChaiOracle');
const ERC20 = artifacts.require("./TestERC20");
const DaiJoin = artifacts.require('DaiJoin');
const GemJoin = artifacts.require('./GemJoin');
const Vat = artifacts.require('./Vat');
const Pot = artifacts.require('./Pot');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');

contract('ChaiOracle', async (accounts) =>  {
    let [ owner ] = accounts;
    let vat;
    let pot;
    let dai;
    let weth;
    let daiJoin;
    let wethJoin;
    let chaiOracle;

    const ilk = web3.utils.fromAscii("ETH-A")
    const Line = web3.utils.fromAscii("Line")
    const spot = web3.utils.fromAscii("spot")
    const linel = web3.utils.fromAscii("line")

    const RAY  = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('45');
    const supply = web3.utils.toWei("1000");
    const limits =  web3.utils.toBN('10000').mul(web3.utils.toBN('10').pow(RAD)).toString(); // 10000 * 10**45
    const chi  = "1250000000000000000000000000"; // 1.25
    const price  = "800000000000000000000000000"; // 0.8

    beforeEach(async() => {
        // Set up vat, join and weth
        vat = await Vat.new();
        await vat.rely(vat.address, { from: owner });

        weth = await ERC20.new(supply, { from: owner }); 
        await vat.init(ilk, { from: owner }); // Set ilk rate to 1.0
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });

        dai = await ERC20.new(supply, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spot,    RAY, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });

        // Setup chaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });
        
        // Set chi to 1.25
        await pot.setChi(chi, { from: owner });
    });

    it("retrieves chai price as 1/pot.chi", async() => {
        assert.equal(
            await chaiOracle.price.call({ from: owner }), // price() is a transaction
            price,
            "Should be 0.8",
        );
    });
});