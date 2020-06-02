const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const Chai = artifacts.require('./Chai');
const ChaiOracle = artifacts.require('./ChaiOracle');
const Treasury = artifacts.require('Treasury');
const YDai = artifacts.require('YDai');
const Mint = artifacts.require('Mint');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('Treasury', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let pot;
    let chai;
    let chaiOracle;
    let treasury;
    let yDai;
    let mint;

    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")

    const limits =  toRad(10000);
    const spot1 = toRay(1.5);
    const rate1 = toRay(1.25);

    const chi1 = toRay(1.2);
    const chi2  = toRay(1.5);
    const chiDifferential  = divRay(chi2, chi1); // 1.5 / 1.2 = 1.25

    const daiTokens1 = toWad(120);
    // const wethTokens1 = divRay(daiTokens1, spot1);
    const wethTokens1 = toWad(120); // TODO: Not right

    const daiTokens2 = mulRay(daiTokens1, chiDifferential);    // 120 * 1.25 - More dai is returned as chi increases
    const wethTokens2 = mulRay(wethTokens1, chiDifferential);   // 80 * 1.25 - As chi increases, we need more collateral to borrow dai from vat
    const savings2 = web3.utils.toWei("187.5"); // TODO: Why?  // 150 * 1.25 - As chi increases, the dai in Treasury grows
    const daiSurplus = subBN(daiTokens2, daiTokens1);
    const savingsSurplus = subBN(savings2, daiTokens2);  // savings2 - daiTokens2

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        // Set up vat, join and weth
        vat = await Vat.new();

        weth = await Weth.new({ from: owner });
        await vat.init(ilk, { from: owner }); // Set ilk rate to 1.0
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spotName, spot1, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); // TODO: Why can't we specify `, { from: owner }`?
        await vat.fold(ilk, vat.address, subBN(rate1, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        // Setup pot
        pot = await Pot.new(vat.address);
        await pot.setChi(chi1, { from: owner });

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
        );

        // Permissions
        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.rely(pot.address, { from: owner });
        await vat.hope(daiJoin.address, { from: owner });
        await vat.hope(wethJoin.address, { from: owner });

        // Setup chaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });

        treasury = await Treasury.new(
            dai.address,
            chai.address,
            chaiOracle.address,
            weth.address,
            daiJoin.address,
            wethJoin.address,
            vat.address,
        );

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(vat.address, pot.address, maturity, "Name", "Symbol");

        // Setup mint
        mint = await Mint.new(
            treasury.address,
            dai.address,
            yDai.address,
            { from: owner },
        );
        await yDai.grantAccess(mint.address, { from: owner });
        await treasury.grantAccess(mint.address, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });
    
    it("yDai can't be redeemed before maturity", async() => {
        await truffleAssert.fails(
            mint.redeem(owner, daiTokens1, { from: owner }),
            truffleAssert.REVERT,
            "Mint: yDai is not mature",
        );
    });

    it("yDai can't be minted after maturity", async() => {
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();
        await truffleAssert.fails(
            mint.mint(owner, daiTokens1, { from: owner }),
            truffleAssert.REVERT,
            "Mint: yDai is mature",
        );
    });

    it("mint takes dai and pushes it to Treasury, mints yDai for the user", async() => {
        // Borrow dai
        await weth.deposit({ from: owner, value: wethTokens1 });
        await weth.approve(wethJoin.address, wethTokens1, { from: owner });
        await wethJoin.join(owner, wethTokens1, { from: owner });
        await vat.frob(ilk, owner, owner, owner, wethTokens1, daiTokens1, { from: owner });
        await daiJoin.exit(owner, daiTokens1, { from: owner });

        assert.equal(
            await dai.balanceOf(owner),
            daiTokens1.toString(),
            "Owner does not have dai",
        );
        assert.equal(
            await yDai.balanceOf(owner),
            0,
            "Owner has yDai"
        );
        assert.equal(
            await treasury.savings.call(),
            0,
            "Treasury has savings",
        );
        await dai.approve(mint.address, daiTokens1, { from: owner });
        await mint.mint(owner, daiTokens1, { from: owner });

        assert.equal(
            await treasury.savings.call(),
            daiTokens1.toString(),
            "Treasury should have dai",
        );
        assert.equal(
            await yDai.balanceOf(owner),
            daiTokens1.toString(),
            "Owner should have yDai"
        );
    });

    it("redeem burns yDai to return dai, pulls dai from Treasury", async() => {
        // Post collateral to MakerDAO through Treasury
        await treasury.grantAccess(owner, { from: owner });
        await weth.deposit({ from: owner, value: wethTokens1 });
        await weth.transfer(treasury.address, wethTokens1, { from: owner }); 
        await treasury.pushWeth({ from: owner });
        assert.equal(
            (await vat.urns(ilk, treasury.address)).ink,
            wethTokens1.toString(),
        );

        // Mint some yDai the sneaky way
        await yDai.grantAccess(owner, { from: owner });
        await yDai.mint(owner, daiTokens1, { from: owner });

        // yDai matures
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();

        assert.equal(
            await yDai.balanceOf(owner),
            daiTokens1.toString(),
            "Owner does not have yDai",
        );
        assert.equal(
            await treasury.savings.call(),
            0,
            "Treasury has no savings",
        );

        await yDai.approve(mint.address, daiTokens1, { from: owner });
        await mint.redeem(owner, daiTokens1, { from: owner });

        assert.equal(
            await treasury.debt(),
            daiTokens1.toString(),
            "Treasury should have debt",
        );
        assert.equal(
            await dai.balanceOf(owner),
            daiTokens1.toString(),
            "Owner should have dai",
        );
    });

    it("redeem with increased chi returns more dai", async() => {
        // Owner is going to mint `daiTokens2` (150) yDai, but after the chi raises he is going to redeem `daiTokens1` (120)
        // As a result, after redeeming, owner will have `daiTokens2` (150) dai and another 30 yDai left
        // Borrow dai
        await weth.deposit({ from: owner, value: wethTokens2 });
        await weth.approve(wethJoin.address, wethTokens2, { from: owner });
        await wethJoin.join(owner, wethTokens2, { from: owner });
        await vat.frob(ilk, owner, owner, owner, wethTokens2, daiTokens2, { from: owner });
        await daiJoin.exit(owner, daiTokens2, { from: owner });
        
        // Mint yDai
        await dai.approve(mint.address, daiTokens2, { from: owner });
        await mint.mint(owner, daiTokens2, { from: owner });

        // yDai matures
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();

        // Chi increases
        await pot.setChi(chi2, { from: owner });
        
        assert(
            await yDai.chi.call(),
            chiDifferential.toString(),
            "chi differential should be " + chiDifferential + ", instead is " + (await yDai.chi.call()),
        );
        assert.equal(
            await yDai.balanceOf(owner),
            daiTokens2.toString(),
            "Owner does not have yDai",
        );
        assert.equal(
            await treasury.savings.call(),
            savings2.toString(), // The increased chi affects the savings in Treasury as well
            "Treasury should have " + savings2 + " dai saved, instead has " + (await treasury.savings.call()),
        );
        assert.equal(
            await dai.balanceOf(mint.address),
            0,
            "Mint has dai",
        );

        await yDai.approve(mint.address, daiTokens1, { from: owner });
        await mint.redeem(owner, daiTokens1, { from: owner });

        assert.equal(
            await dai.balanceOf(owner),
            daiTokens2.toString(),
            "Owner should have " + daiTokens2 + ", instead has " + (await dai.balanceOf(owner)),
        );
        assert.equal(
            await yDai.balanceOf(owner),
            daiSurplus.toString(),
            "Owner should have " + daiSurplus + " dai surplus, instead has " + (await yDai.balanceOf(owner)),
        );
        assert.equal(
            await dai.balanceOf(mint.address),
            0,
            "Mint should have no dai",
        );
        assert.equal(
            await treasury.savings.call(),
            savingsSurplus.toString(),
            "Treasury should have some savings",
        );
    });
});