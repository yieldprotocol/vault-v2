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
const { expectRevert, expectEvent } = require('@openzeppelin/test-helpers');

contract('yDai', async (accounts) =>  {
    let [ owner, holder, other ] = accounts;
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
    const spot = toRay(1.5);
    const rate1 = toRay(1.2);
    const chi1 = toRay(1.3);
    const rate2 = toRay(1.5);
    const chi2 = toRay(1.82);

    const chiDifferential  = divRay(chi2, chi1); // 1.82 / 1.3 = 1.4

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
        await yDai.mint(holder, daiTokens1, { from: owner });

        // yDai matures
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();

        assert.equal(
            await yDai.balanceOf(holder),
            daiTokens1.toString(),
            "Holder does not have yDai",
        );
        assert.equal(
            await treasury.savings.call(),
            0,
            "Treasury has no savings",
        );
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("redeem is allowed for account holder", async() => {
        await yDai.approve(yDai.address, daiTokens1, { from: holder });
        await yDai.redeem(holder, daiTokens1, { from: holder });

        assert.equal(
            await treasury.debt(),
            daiTokens1.toString(),
            "Treasury should have debt",
        );
        assert.equal(
            await dai.balanceOf(holder),
            daiTokens1.toString(),
            "Holder should have dai",
        );
    });

    it("redeem is not allowed for non designated accounts", async() => {
        await yDai.approve(yDai.address, daiTokens1, { from: holder });
        await expectRevert(
            yDai.redeem(holder, daiTokens1, { from: other }),
            "YDai: Only Holder Or Proxy",
        );
    });

    it("redeem is allowed for designated proxies", async() => {
        await yDai.approve(yDai.address, daiTokens1, { from: holder });
        expectEvent(
            await yDai.addProxy(other, { from: holder }),
            "Proxy",
            {
                user: holder,
                proxy: other,
                enabled: true,
            },
        );
        await yDai.redeem(holder, daiTokens1, { from: other });

        assert.equal(
            await treasury.debt(),
            daiTokens1.toString(),
            "Treasury should have debt",
        );
        assert.equal(
            await dai.balanceOf(holder),
            daiTokens1.toString(),
            "Holder should have dai",
        );
    });

    describe("with designated proxies", async() => {
        beforeEach(async() => {
            await yDai.addProxy(other, { from: holder });
        });

        it("redeem is not allowed if proxy revoked", async() => {
            expectEvent(
                await yDai.revokeProxy(other, { from: holder }),
                "Proxy",
                {
                    user: holder,
                    proxy: other,
                    enabled: false,
                },
            );

            await expectRevert(
                yDai.redeem(holder, daiTokens1, { from: other }),
                "YDai: Only Holder Or Proxy",
            );
        });
    });
});