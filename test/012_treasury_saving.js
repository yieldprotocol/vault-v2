const Treasury = artifacts.require('./Treasury');
const Chai = artifacts.require('./Chai');
const ChaiOracle = artifacts.require('ChaiOracle');
const ERC20 = artifacts.require("./TestERC20");
const DaiJoin = artifacts.require('DaiJoin');
const GemJoin = artifacts.require('./GemJoin');
const Vat= artifacts.require('./Vat');
const Pot= artifacts.require('./Pot');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');

contract('Treasury', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let treasury;
    let vat;
    let pot;
    let chai;
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
    let wethTokens = web3.utils.toWei("110");
    let daiTokens = web3.utils.toWei("110");
    let chaiTokens = web3.utils.toWei("100");
    const chi  = "1100000000000000000000000000";

    beforeEach(async() => {
        // Set up vat, join and weth
        vat = await Vat.new();
        await vat.rely(vat.address, { from: owner });

        weth = await ERC20.new(supply, { from: owner }); 
        await vat.init(ilk, { from: owner }); // Set ilk rate to 1.0
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spot,    RAY, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
        );

        // Setup chaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });

        // Borrow dai
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });
        await weth.approve(wethJoin.address, wethTokens, { from: owner });
        await wethJoin.join(owner, wethTokens, { from: owner });
        await vat.frob(ilk, owner, owner, owner, wethTokens, daiTokens, { from: owner });
        await daiJoin.exit(owner, daiTokens, { from: owner });

        // Set chi to 1.1
        await pot.setChi(chi, { from: owner });
        
        treasury = await Treasury.new(
            dai.address,        // dai
            chai.address,       // chai
            chaiOracle.address, // chaiOracle
            weth.address,       // weth
            daiJoin.address,    // daiJoin
            wethJoin.address,   // wethJoin
            vat.address,        // vat
        );
        await treasury.grantAccess(owner, { from: owner });
    });

    it("allows to save dai", async() => {
        assert.equal(
            (await chai.balanceOf(treasury.address)),   
            0,
            "Treasury has chai",
        );
        assert.equal(
            (await treasury.savings.call()),   
            0,
            "Treasury has savings in dai units"
        );
        assert.equal(
            (await dai.balanceOf(owner)),   
            daiTokens,
            "User does not have dai",
        );
        
        await dai.transfer(treasury.address, daiTokens, { from: owner }); 
        await treasury.pushDai({ from: owner });

        // Test transfer of collateral
        assert.equal(
            (await chai.balanceOf(treasury.address)),   
            chaiTokens,
            "Treasury should have chai"
        );
        assert.equal(
            (await treasury.savings.call()),   
            daiTokens,
            "Treasury should report savings in dai units"
        );
        assert.equal(
            (await dai.balanceOf(owner)),   
            0,
            "User should not have dai",
        );
    });

    it("allows to save chai", async() => {
        assert.equal(
            (await chai.balanceOf(treasury.address)),   
            0,
            "Treasury has chai",
        );
        assert.equal(
            (await treasury.savings.call()),   
            0,
            "Treasury has savings in dai units"
        );
        assert.equal(
            (await dai.balanceOf(owner)),   
            daiTokens,
            "User does not have dai",
        );
        
        await dai.approve(chai.address, daiTokens, { from: owner });
        await chai.join(owner, daiTokens, { from: owner });
        await chai.transfer(treasury.address, chaiTokens, { from: owner }); 
        await treasury.pushChai({ from: owner });

        // Test transfer of collateral
        assert.equal(
            (await chai.balanceOf(treasury.address)),   
            chaiTokens,
            "Treasury should have chai"
        );
        assert.equal(
            (await treasury.savings.call()),   
            daiTokens,
            "Treasury should report savings in dai units"
        );
        assert.equal(
            (await chai.balanceOf(owner)),   
            0,
            "User should not have chai",
        );
    });

    describe("with savings", () => {
        beforeEach(async() => {
            await dai.transfer(treasury.address, daiTokens, { from: owner }); 
            await treasury.pushDai({ from: owner });
        });

        it("pulls dai from savings", async() => {
            assert.equal(
                (await chai.balanceOf(treasury.address)),   
                chaiTokens,
                "Treasury does not have chai"
            );
            assert.equal(
                (await treasury.savings.call()),   
                daiTokens,
                "Treasury does not report savings in dai units"
            );
            assert.equal(
                (await dai.balanceOf(owner)),   
                0,
                "User has dai",
            );
            
            await treasury.pullDai(owner, daiTokens, { from: owner });

            assert.equal(
                (await chai.balanceOf(treasury.address)),   
                0,
                "Treasury should not have chai",
            );
            assert.equal(
                (await treasury.savings.call()),   
                0,
                "Treasury should not have savings in dai units"
            );
            assert.equal(
                (await dai.balanceOf(owner)),   
                daiTokens,
                "User should have dai",
            );
        });


        it("pulls chai from savings", async() => {
            assert.equal(
                (await chai.balanceOf(treasury.address)),   
                chaiTokens,
                "Treasury does not have chai"
            );
            assert.equal(
                (await treasury.savings.call()),   
                daiTokens,
                "Treasury does not report savings in dai units"
            );
            assert.equal(
                (await dai.balanceOf(owner)),   
                0,
                "User has dai",
            );
            
            await treasury.pullChai(owner, chaiTokens, { from: owner });

            assert.equal(
                (await chai.balanceOf(treasury.address)),   
                0,
                "Treasury should not have chai",
            );
            assert.equal(
                (await treasury.savings.call()),   
                0,
                "Treasury should not have savings in dai units"
            );
            assert.equal(
                (await chai.balanceOf(owner)),   
                chaiTokens,
                "User should have chai",
            );
        });
    });
});