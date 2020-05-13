const Mint = artifacts.require('Mint');
const Lender = artifacts.require('Lender');
const Saver = artifacts.require('Saver');
const Chai = artifacts.require('Chai');
const ChaiOracle = artifacts.require('ChaiOracle');
const YDai = artifacts.require('YDai');
const ERC20 = artifacts.require('TestERC20');
const DaiJoin = artifacts.require('DaiJoin');
const GemJoin = artifacts.require('GemJoin');
const Vat= artifacts.require('Vat');
const Pot= artifacts.require('Pot');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { BN } = require('@openzeppelin/test-helpers');

let snapshot;
let snapshotId;

contract('Mint', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let pot;
    let lender;
    let saver;
    let dai;
    let yDai;
    let chai;
    let chaiOracle;
    let weth;
    let daiJoin;
    let wethJoin;
    let mint;
    const daiTokens = web3.utils.toWei("110");
    const chaiTokens = web3.utils.toWei("100");
    const chi = "1100000000000000000000000000";

    const ilk = web3.utils.fromAscii("ETH-A")
    const Line = web3.utils.fromAscii("Line")
    const spot = web3.utils.fromAscii("spot")
    const linel = web3.utils.fromAscii("line")

    const RAY  = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('45');
    const supply = web3.utils.toWei("1000");
    const limits =  web3.utils.toBN('10000').mul(web3.utils.toBN('10').pow(RAD)).toString(); // 10000 * 10**45

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

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
        );
        await vat.rely(chai.address, { from: owner });

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

        // Setup saver
        saver = await Saver.new(chai.address);

        // Setup chaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });

        // Setup mint
        mint = await Mint.new(
            lender.address,
            saver.address,
            dai.address,
            yDai.address,
            chai.address,
            chaiOracle.address,
            { from: owner },
        );
        await yDai.grantAccess(mint.address, { from: owner });
        await lender.grantAccess(mint.address, { from: owner });
        await saver.grantAccess(mint.address, { from: owner });

        // Allow owner to borrow dai
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });

        // Set chi to 1.1
        await pot.setChi(chi, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });
    
    it("yDai can't be redeemed before maturity", async() => {
        await truffleAssert.fails(
            mint.redeem(owner, daiTokens, { from: owner }),
            truffleAssert.REVERT,
            "Mint: yDai is not mature",
        );
    });

    it("mintNoDebt: mints yDai in exchange for dai, chai goes to Saver", async() => {
        // Borrow dai
        let wethTokens = web3.utils.toWei("500");
        await weth.approve(wethJoin.address, wethTokens, { from: owner });
        await wethJoin.join(owner, wethTokens, { from: owner });
        await vat.frob(ilk, owner, owner, owner, wethTokens, daiTokens, { from: owner });
        await daiJoin.exit(owner, daiTokens, { from: owner });

        assert.equal(
            (await dai.balanceOf(owner)),   
            daiTokens,
            "Owner does not have dai",
        );
        assert.equal(
            (await chai.balanceOf(mint.address)),   
            0,
            "Mint has chai",
        );
        assert.equal(
            (await yDai.balanceOf(owner)),   
            0,
            "Owner has yDai"
        );
        assert.equal(
            (await dai.balanceOf(mint.address)),   
            0,
            "Mint has dai",
        );
        assert.equal(
            (await lender.debt()),   
            0,
            "Lender has debt",
        );
        await dai.approve(mint.address, daiTokens, { from: owner });
        await mint.mint(owner, daiTokens, { from: owner });

        assert.equal(
            (await chai.balanceOf(saver.address)),   
            chaiTokens,
            "Saver should have " + chaiTokens + " chai, instead has " + BN(await chai.balanceOf(saver.address)).toString(),
        );
        assert.equal(
            (await yDai.balanceOf(owner)),   
            daiTokens,
            "Owner should have yDai"
        );
        assert.equal(
            (await dai.balanceOf(mint.address)),   
            0,
            "Mint should have no dai",
        );
    });

    it("redeemNoSavings: burns yDai to return dai, borrows dai from Lender", async() => {
        // yDai matures
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();
        // Some other user posted collateral to MakerDAO through Lender
        await lender.grantAccess(user, { from: owner });
        await weth.mint(user, daiTokens, { from: user });
        await weth.approve(lender.address, daiTokens, { from: user }); 
        await lender.post(user, daiTokens, { from: user });
        let ink = (await vat.urns(ilk, lender.address)).ink.toString()
        assert.equal(
            ink,   
            daiTokens
        );

        // Mint some yDai the sneaky way
        await yDai.grantAccess(owner, { from: owner });
        await yDai.mint(owner, daiTokens, { from: owner });

        assert.equal(
            (await yDai.balanceOf(owner)),   
            daiTokens,
            "Owner does not have yDai",
        );
        assert.equal(
            (await saver.savings()),   
            0,
            "Saver has no savings",
        );

        await yDai.approve(mint.address, daiTokens, { from: owner });
        await mint.redeem(owner, daiTokens, { from: owner });
        assert.equal(
            (await lender.debt()),   
            daiTokens,
            "Lender should have debt",
        );
        assert.equal(
            (await dai.balanceOf(owner)),   
            daiTokens,
            "Owner should have dai",
        );
        assert.equal(
            (await dai.balanceOf(mint.address)),   
            0,
            "Mint should have no dai",
        );
    });

    it("redeemSavings: burns yDai to return dai, pulls chai from Saver", async() => {
        // yDai matures
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();
        // Borrow dai
        let wethTokens = web3.utils.toWei("500");
        await weth.approve(wethJoin.address, wethTokens, { from: owner });
        await wethJoin.join(owner, wethTokens, { from: owner });
        await vat.frob(ilk, owner, owner, owner, wethTokens, daiTokens, { from: owner });
        await daiJoin.exit(owner, daiTokens, { from: owner });
        // Mint yDai
        await dai.approve(mint.address, daiTokens, { from: owner });
        await mint.mint(owner, daiTokens, { from: owner });

        assert.equal(
            (await yDai.balanceOf(owner)),   
            daiTokens,
            "Owner does not have yDai",
        );
        assert.equal(
            (await chai.balanceOf(saver.address)),   
            chaiTokens,
            "Saver does not have chai",
        );
        assert.equal(
            (await saver.savings()),   
            chaiTokens,
            "Saver does not have savings",
        );
        assert.equal(
            (await dai.balanceOf(mint.address)),   
            0,
            "Mint has dai",
        );

        await yDai.approve(mint.address, daiTokens, { from: owner });
        await mint.redeem(owner, daiTokens, { from: owner });

        assert.equal(
            (await dai.balanceOf(owner)),   
            daiTokens,
            "Owner should have dai",
        );
        assert.equal(
            (await dai.balanceOf(mint.address)),   
            0,
            "Mint should have no dai",
        );
        assert.equal(
            (await chai.balanceOf(saver.address)),   
            0,
            "Saver should not have chai",
        );
    });

    it("mintDebt: mints yDai in exchange for dai, dai repays Lender debt", async() => {
        // yDai matures
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();
        // Mint some yDai the sneaky way
        await yDai.grantAccess(owner, { from: owner });
        await yDai.mint(owner, daiTokens, { from: owner });

        // Some other user posted collateral to MakerDAO through Lender, so that Lender can borrow dai
        await lender.grantAccess(user, { from: owner });
        await weth.mint(user, daiTokens, { from: user });
        await weth.approve(lender.address, daiTokens, { from: user }); 
        await lender.post(user, daiTokens, { from: user });
        let ink = (await vat.urns(ilk, lender.address)).ink.toString()
        assert.equal(
            ink,   
            daiTokens,
        );

        // Someone redeems yDai, using up the collateral and causing Lender debt
        await yDai.approve(mint.address, daiTokens, { from: owner });
        await mint.redeem(owner, daiTokens, { from: owner });
        assert.equal(
            (await lender.debt()),
            daiTokens,
        );

        assert.equal(
            (await dai.balanceOf(owner)),   
            daiTokens,
            "Owner does not have dai",
        );
        assert.equal(
            (await chai.balanceOf(mint.address)),   
            0,
            "Mint has chai",
        );
        assert.equal(
            (await yDai.balanceOf(owner)),   
            0,
            "Owner has yDai"
        );
        assert.equal(
            (await lender.debt()),
            daiTokens,
            "Lender doesn't have debt",
        );

        await dai.approve(mint.address, daiTokens, { from: owner });
        await mint.mint(owner, daiTokens, { from: owner });

        assert.equal(
            (await lender.debt()),
            0,
            "Lender shouldn't have debt",
        );
        assert.equal(
            (await yDai.balanceOf(owner)),   
            daiTokens,
            "Owner should have yDai"
        );
        assert.equal(
            (await dai.balanceOf(mint.address)),   
            0,
            "Mint should have no dai",
        );
    });
});