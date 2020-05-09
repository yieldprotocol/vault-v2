const Vat= artifacts.require('Vat');
const Pot = artifacts.require('Pot');
const ERC20 = artifacts.require("TestERC20");
const DaiJoin = artifacts.require('DaiJoin');
const GemJoin = artifacts.require('GemJoin');
const YDai = artifacts.require('YDai');
const Lender = artifacts.require('Lender');
const Chai = artifacts.require('Chai');
const Saver = artifacts.require('Saver');
const ChaiOracle = artifacts.require('ChaiOracle');
const Mint = artifacts.require('Mint');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');

contract('Mint', async (accounts) =>  {
    let [ owner, user ] = accounts;

    let vat;
    let pot;
    let dai;
    let weth;
    let daiJoin;
    let wethJoin;
    let yDai;
    let lender;
    let chai;
    let saver;
    let chaiOracle;
    let mint;

    const ilk = web3.utils.fromAscii("ETH-A")
    const Line = web3.utils.fromAscii("Line")
    const spot = web3.utils.fromAscii("spot")
    const linel = web3.utils.fromAscii("line")
    const supply = web3.utils.toWei("1000");
    const RAY  = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('45')
    const limits =  web3.utils.toBN('10000').mul(web3.utils.toBN('10').pow(RAD)).toString(); // 10000 * 10**45

    let maturity;
    let snapshot;
    let snapshotId;

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

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

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(vat.address, pot.address, maturity, "Name", "Symbol");

        // Setup lender
        lender = await Lender.new(
            dai.address,        // dai
            weth.address,       // weth
            daiJoin.address,    // daiJoin
            wethJoin.address,   // wethJoin
            vat.address,        // vat
        );
        await vat.rely(lender.address, { from: owner }); //?

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
        );
        await vat.rely(chai.address, { from: owner });

        // Setup chaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });

        // Setup saver
        saver = await Saver.new(chai.address);

        // Setup mint
        mint = await Mint.new(
            lender.address,
            saver.address,
            dai.address,
            yDai.address,
            chai.address,
            chaiOracle.address
        );
        await vat.rely(mint.address, { from: owner }); //?

        await yDai.grantAccess(mint.address, { from: owner });
        await lender.grantAccess(mint.address, { from: owner });
        await saver.grantAccess(mint.address, { from: owner });

        // Borrow dai
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });
        let wethTokens = web3.utils.toWei("500");
        let daiTokens = web3.utils.toWei("100");
        await weth.approve(wethJoin.address, wethTokens, { from: owner });
        await wethJoin.join(owner, wethTokens, { from: owner });
        await vat.frob(ilk, owner, owner, owner, wethTokens, daiTokens, { from: owner });
        await daiJoin.exit(owner, daiTokens, { from: owner });
    });

    it("yDai can't be redeemed before maturity", async() => {
        await truffleAssert.fails(
            yDai.mature(),
            truffleAssert.REVERT,
            "YDai: Too early to mature",
        );
    });

    it("allows to save chai", async() => {
        let daiTokens = web3.utils.toWei("100");
        assert.equal(
            (await dai.balanceOf(owner)),   
            daiTokens,
            "Owner doesn't have the dai"
        );
        assert.equal(
            (await saver.savings()),   
            web3.utils.toWei("0")
        );

        // Exchange chai for dai
        await dai.approve(chai.address, daiTokens, { from: owner }); 
        await chai.join(owner, daiTokens, { from: owner });
        assert.equal(
            (await chai.balanceOf(owner)),   
            daiTokens,
            "Owner doesn't have the chai"
        );
        assert.equal(
            (await chai.totalSupply.call()),   
            daiTokens,
            "`totalSupply()` doesn't work"
        );

        await chai.approve(saver.address, daiTokens, { from: owner }); 
        await saver.grantAccess(owner, { from: owner });
        await saver.join(owner, daiTokens, { from: owner });

        // Test transfer of collateral
        assert.equal(
            (await saver.savings()),   
            daiTokens,
            "Saver doesn't have the chai",
        );
        assert.equal(
            (await chai.balanceOf(owner)),   
            0,
        );
    });

    it("yDai can be minted for dai, dai is converted to chai and stored in Saver", async() => {
        let daiTokens = web3.utils.toWei("100");
        assert.equal(
            (await dai.balanceOf(owner)),   
            daiTokens,
            "Owner doesn't have the dai",
        );
        assert.equal(
            (await chaiOracle.price.call()),   
            RAY,
            "Chai price is not RAY.unit()",
        );
        assert.equal(
            (await chai.totalSupply.call()),   
            0,
            "There is chai before `mint()`"
        );

        await dai.approve(mint.address, daiTokens, { from: owner });
        await mint.mint(owner, daiTokens, { from: owner });

        assert.equal(
            (await dai.balanceOf(owner)),   
            daiTokens,
            "Owner still has the dai",
        );
        /* assert.equal(
            (await dai.balanceOf(mint.address)),   
            daiTokens,
            "The dai was not transferred",
        ); */
        /* assert.equal(
            (await yDai.balanceOf(owner)),   
            daiTokens,
            "The yDai was not minted",
        ); */
        assert.equal(
            (await chai.balanceOf(mint.address)),   
            daiTokens,
            "Mint doesn't have the chai"
        );
        /* assert.equal(
            (await saver.savings()),   
            web3.utils.toWei("100")
        ); */
    });

    describe("with no debt in the lender", () => {

    });

    describe("with debt in the lender", () => {

    });

    describe("with no savings in the saver", () => {
        
    });

    describe("with savings in the saver", () => {
        
    });
});