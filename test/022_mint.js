const Mint = artifacts.require('Mint');
const Treasury = artifacts.require('Treasury');
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
    let treasury;
    let dai;
    let yDai;
    let chai;
    let chaiOracle;
    let weth;
    let daiJoin;
    let wethJoin;
    let mint;

    const ilk = web3.utils.fromAscii("ETH-A")
    const Line = web3.utils.fromAscii("Line")
    const spot = web3.utils.fromAscii("spot")
    const linel = web3.utils.fromAscii("line")

    const RAY  = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('45');
    const supply = web3.utils.toWei("1000");
    const limits =  web3.utils.toBN('10000').mul(web3.utils.toBN('10').pow(RAD)).toString(); // 10000 * 10**45

    const originalChi = "1200000000000000000000000000";        // 1.2
    const finalChi  = "1500000000000000000000000000";          // 1.5
    const chiDifferential  = "12500000000000000000000000000";  // 1.25 = 1.5 / 1.2

    const wethTokens = web3.utils.toWei("120");
    const daiTokens = web3.utils.toWei("120");

    const moreDai = web3.utils.toWei("150");    // 120 * 1.25 - More dai is returned as chi increases
    const moreWeth = web3.utils.toWei("150");   // 120 * 1.25 - As chi increases, we need more collateral to borrow dai from vat
    const moreSavings = web3.utils.toWei("187.5");   // 150 * 1.25 - As chi increases, the dai in Treasury grows
    const daiSurplus = web3.utils.toWei("30");  // moreDai - daiTokens
    const savingsSurplus = web3.utils.toWei("37.5");  // moreSavings - moreDai

    const chaiTokens = web3.utils.toWei("100"); // daiTokens / 1.2

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

        // Setup chaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(vat.address, pot.address, maturity, "Name", "Symbol");

        // Setup treasury
        treasury = await Treasury.new(
            dai.address,        // dai
            chai.address,       // chai
            chaiOracle.address, // chaiOracle
            weth.address,       // weth
            daiJoin.address,    // daiJoin
            wethJoin.address,   // wethJoin
            vat.address,        // vat
        );

        // Setup mint
        mint = await Mint.new(
            treasury.address,
            dai.address,
            yDai.address,
            { from: owner },
        );
        await yDai.grantAccess(mint.address, { from: owner });
        await treasury.grantAccess(mint.address, { from: owner });

        // Allow owner to borrow dai
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });

        // Set chi
        await pot.setChi(originalChi, { from: owner });
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

    it("yDai can't be minted after maturity", async() => {
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();
        await truffleAssert.fails(
            mint.mint(owner, daiTokens, { from: owner }),
            truffleAssert.REVERT,
            "Mint: yDai is mature",
        );
    });

    it("mint takes dai and pushes it to Treasury, mints yDai for the user", async() => {
        // Borrow dai
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
            (await yDai.balanceOf(owner)),   
            0,
            "Owner has yDai"
        );
        assert.equal(
            (await treasury.savings.call()),   
            0,
            "Treasury has savings",
        );
        await dai.approve(mint.address, daiTokens, { from: owner });
        await mint.mint(owner, daiTokens, { from: owner });

        assert.equal(
            (await treasury.savings.call()),   
            daiTokens,
            "Treasury should have dai",
        );
        assert.equal(
            (await yDai.balanceOf(owner)),   
            daiTokens,
            "Owner should have yDai"
        );
    });

    it("redeem burns yDai to return dai, pulls dai from Treasury", async() => {
        // Post collateral to MakerDAO through Treasury
        await treasury.grantAccess(owner, { from: owner });
        await weth.mint(user, wethTokens, { from: owner });
        await weth.transfer(treasury.address, wethTokens, { from: owner }); 
        await treasury.pushWeth({ from: owner });
        let ink = (await vat.urns(ilk, treasury.address)).ink.toString()
        assert.equal(
            ink,   
            wethTokens
        );

        // Mint some yDai the sneaky way
        await yDai.grantAccess(owner, { from: owner });
        await yDai.mint(owner, daiTokens, { from: owner });

        // yDai matures
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();

        assert.equal(
            (await yDai.balanceOf(owner)),   
            daiTokens,
            "Owner does not have yDai",
        );
        assert.equal(
            (await treasury.savings.call()),   
            0,
            "Treasury has no savings",
        );

        await yDai.approve(mint.address, daiTokens, { from: owner });
        await mint.redeem(owner, daiTokens, { from: owner });

        assert.equal(
            (await treasury.debt()),   
            daiTokens,
            "Treasury should have debt",
        );
        assert.equal(
            (await dai.balanceOf(owner)),   
            daiTokens,
            "Owner should have dai",
        );
    });

    it("redeem with increased chi returns more dai", async() => {
        // Owner is going to mint `moreDai` (150) yDai, but after the chi raises he is going to redeem `daiTokens` (120)
        // As a result, after redeeming, owner will have `moreDai` (150) dai and another 30 yDai left
        // Borrow dai
        await weth.approve(wethJoin.address, moreWeth, { from: owner });
        await wethJoin.join(owner, moreWeth, { from: owner });
        await vat.frob(ilk, owner, owner, owner, moreWeth, moreDai, { from: owner });
        await daiJoin.exit(owner, moreDai, { from: owner });
        
        // Mint yDai
        await dai.approve(mint.address, moreDai, { from: owner });
        await mint.mint(owner, moreDai, { from: owner });

        // yDai matures
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();

        // Chi increases
        await pot.setChi(finalChi, { from: owner });
        
        assert(
            await yDai.chi.call(),
            chiDifferential,
            "chi differential should be " + chiDifferential + ", instead is " + (await yDai.chi.call()),
        );
        assert.equal(
            (await yDai.balanceOf(owner)),   
            moreDai,
            "Owner does not have yDai",
        );
        assert.equal(
            (await treasury.savings.call()),
            moreSavings, // The increased chi affects the savings in Treasury as well
            "Treasury should have " + moreSavings + " dai saved, instead has " + (await treasury.savings.call()),
        );
        assert.equal(
            (await dai.balanceOf(mint.address)),   
            0,
            "Mint has dai",
        );

        await yDai.approve(mint.address, daiTokens, { from: owner });
        await mint.redeem(owner, daiTokens, { from: owner });

        const obtainedDai = new BN(await dai.balanceOf(owner));
        assert.equal(
            obtainedDai,   
            moreDai,
            "Owner should have " + moreDai + ", instead has " + obtainedDai,
        );
        assert.equal(
            (await yDai.balanceOf(owner)),   
            daiSurplus,
            "Owner should have " + daiSurplus + " dai surplus, instead has " + (await yDai.balanceOf(owner)),
        );
        assert.equal(
            (await dai.balanceOf(mint.address)),   
            0,
            "Mint should have no dai",
        );
        assert.equal(
            (await treasury.savings.call()),   
            savingsSurplus,
            "Treasury should have some savings",
        );
    });
});