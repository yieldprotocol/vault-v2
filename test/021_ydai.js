const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require('WETH9');
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const Chai = artifacts.require('Chai');
const ChaiOracle = artifacts.require('ChaiOracle');
const Treasury = artifacts.require('Treasury');
const YDai = artifacts.require('YDai');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');
const { expectRevert } = require('@openzeppelin/test-helpers');

contract('yDai', async (accounts) =>  {
    let [ owner ] = accounts;
    let vat;
    let pot;
    let chai;
    let chaiOracle;
    let treasury;
    let yDai;
    let maturity;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")

    const limits =  toRad(10000);
    const spot = toRay(1.2);

    const rate1 = toRay(1.5);
    const chi1 = toRay(1.2);
    const rate2 = toRay(1.82);
    const chi2 = toRay(1.5);


    const chiDifferential  = divRay(chi2, chi1);

    const daiDebt1 = toWad(96);
    const daiTokens1 = mulRay(daiDebt1, rate1);
    const wethTokens1 = divRay(daiTokens1, spot);

    const daiTokens2 = mulRay(daiTokens1, chiDifferential);
    const wethTokens2 = mulRay(wethTokens1, chiDifferential)

    // Scenario in which the user mints daiTokens2 yDai, chi increases by a 25%, and user redeems daiTokens1 yDai
    const daiDebt2 = mulRay(daiDebt1, chiDifferential);
    const savings1 = daiTokens2;
    const savings2 = mulRay(savings1, chiDifferential);
    const yDaiSurplus = subBN(daiTokens2, daiTokens1);
    const savingsSurplus = subBN(savings2, daiTokens2);

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        // Set up vat, join and weth
        vat = await Vat.new();
        await vat.init(ilk, { from: owner }); // Set ilk rate to 1.0

        weth = await Weth.new({ from: owner });
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spotName, spot, { from: owner });
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
        yDai = await YDai.new(
            vat.address,
            pot.address,
            treasury.address,
            maturity,
            "Name",
            "Symbol"
        );
        await treasury.grantAccess(yDai.address, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("should setup yDai", async() => {
        assert(
            await yDai.chi.call(),
            toRay(1.0).toString(),
            "chi not initialized",
        );
        assert(
            await yDai.rate(),
            toRay(1.0).toString(),
            "rate not initialized",
        );
        assert(
            await yDai.maturity(),
            maturity.toString(),
            "maturity not initialized",
        );
    });

    it("yDai is not mature before maturity", async() => {
        assert.equal(
            await yDai.isMature(),
            false,
        );
    });

    it("yDai cannot mature before maturity time", async() => {
        await expectRevert(
            yDai.mature(),
            "YDai: Too early to mature",
        );
    });

    it("yDai can mature at maturity time", async() => {
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();
        assert.equal(
            await yDai.isMature(),
            true,
        );
    });

    it("yDai can't mature more than once", async() => {
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();
        await expectRevert(
            yDai.mature(),
            "YDai: Already mature",
        );
    });

    describe("once mature", () => {
        beforeEach(async() => {
            await helper.advanceTime(1000);
            await helper.advanceBlock();
        });

        it("yDai chi gets fixed at maturity time", async() => {
            await yDai.mature();
            await pot.setChi(chi2, { from: owner });
            assert(
                await yDai.chi.call(),
                subBN(chi2, chi1).toString(),
                "Chi differential should be " + subBN(chi2, chi1),
            );
        });

        it("yDai rate gets fixed at maturity time", async() => {
            await yDai.mature();
            await vat.fold(ilk, vat.address, subBN(rate2, rate1), { from: owner });
            assert(
                await yDai.rate(),
                subBN(rate2, rate1).toString(),
                "Rate differential should be " + subBN(rate2, rate1),
            );
        });
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

        await yDai.approve(yDai.address, daiTokens1, { from: owner });
        await yDai.redeem(owner, daiTokens1, { from: owner });

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
        // Owner is going to mint `daiTokens2` yDai, but after the chi raises he is going to redeem `daiTokens1`
        // As a result, after redeeming, owner will have `daiTokens2` dai and another `yDaiSurplus` yDai left
        // Deposit some weth to treasury so that redeem can pull some dai
        await weth.deposit({ from: owner, value: wethTokens2 });
        await weth.transfer(treasury.address, wethTokens2, { from: owner });
        await treasury.grantAccess(owner, { from: owner });
        await treasury.pushWeth();
        
        // Mint some yDai the sneaky way, only difference is that the Dealer doesn't record the user debt.
        await yDai.grantAccess(owner, { from: owner });
        await yDai.mint(owner, daiTokens2, { from: owner });

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

        await yDai.approve(yDai.address, daiTokens1, { from: owner });
        await yDai.redeem(owner, daiTokens1, { from: owner });

        assert.equal(
            await dai.balanceOf(owner),
            daiTokens2.toString(),
            "Owner should have " + daiTokens2 + " dai, instead has " + (await dai.balanceOf(owner)),
        );
        assert.equal(
            await yDai.balanceOf(owner),
            yDaiSurplus.toString(),
            "Owner should have " + yDaiSurplus + " dai surplus, instead has " + (await yDai.balanceOf(owner)),
        );
    });
});