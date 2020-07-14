// External
const Migrations = artifacts.require('Migrations');
const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Jug = artifacts.require('Jug');
const Pot = artifacts.require('Pot');
const End = artifacts.require('End');
const Chai = artifacts.require('Chai');
const GasToken = artifacts.require('GasToken1');

// Common
const Treasury = artifacts.require('Treasury');

// YDai
const YDai = artifacts.require('YDai');
const Controller = artifacts.require('Controller');

// Peripheral
const EthProxy = artifacts.require('EthProxy');
const Unwind = artifacts.require('Unwind');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');
const { expectRevert } = require('@openzeppelin/test-helpers');

contract('yDai', async (accounts) =>  {
    let [ owner, user1, user2 ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let jug;
    let pot;
    let end;
    let chai;
    let gasToken;
    let treasury;
    let yDai0; // yDai0 matures on 2020-09-30
    let yDai4; // yDai4 is a test yDai that passed the maturity date
    let controller;
    let splitter;

    let WETH = web3.utils.fromAscii("ETH-A");

    let rate1;
    let chi1;
    const rate2 = toRay(1.82); // 1.4 -> 1.82
    const chi2 = toRay(1.5); // 1.2 -> 1.5

    let daiDebt1;
    let daiTokens1;
    let wethTokens1;

    beforeEach(async() => {
        const migrations = await Migrations.deployed();

        vat = await Vat.at(await migrations.contracts(web3.utils.fromAscii("Vat")));
        weth = await Weth.at(await migrations.contracts(web3.utils.fromAscii("Weth")));
        wethJoin = await GemJoin.at(await migrations.contracts(web3.utils.fromAscii("WethJoin")));
        dai = await ERC20.at(await migrations.contracts(web3.utils.fromAscii("Dai")));
        daiJoin = await DaiJoin.at(await migrations.contracts(web3.utils.fromAscii("DaiJoin")));
        jug = await Jug.at(await migrations.contracts(web3.utils.fromAscii("Jug")));
        pot = await Pot.at(await migrations.contracts(web3.utils.fromAscii("Pot")));
        chai = await Chai.at(await migrations.contracts(web3.utils.fromAscii("Chai")));
        gasToken = await GasToken.at(await migrations.contracts(web3.utils.fromAscii("GasToken")));
        treasury = await Treasury.at(await migrations.contracts(web3.utils.fromAscii("Treasury")));
        
        spot  = (await vat.ilks(WETH)).spot;
        rate1  = (await vat.ilks(WETH)).rate;
        chi1 = await pot.chi(); // Good boys call drip()

        wethTokens1 = toWad(1);
        daiTokens1 = mulRay(wethTokens1.toString(), spot.toString());
        daiDebt1 = divRay(daiTokens1.toString(), rate1.toString());

        yDai0 = await YDai.at(await migrations.contracts(web3.utils.fromAscii("yDai0")));
        yDai4 = await YDai.at(await migrations.contracts(web3.utils.fromAscii("yDai4")));
    });

    it("yDai are not mature until someone triggers maturation", async() => {
        assert.equal(
            await yDai4.isMature(),
            false,
        );
    });

    it("yDai can't be redeemed if not mature", async() => {
        await expectRevert(
            yDai4.redeem(owner, owner, daiTokens1, { from: owner }),
            "YDai: yDai is not mature",
        );
    });

    it("yDai cannot mature before maturity time", async() => {
        await expectRevert(
            yDai0.mature(),
            "YDai: Too early to mature",
        );
    });

    it("yDai can mature after maturity time", async() => {
        await yDai4.mature();
        assert.equal(
            await yDai4.isMature(),
            true,
        );
    });

    it("yDai can't mature more than once", async() => {
        await expectRevert(
            yDai4.mature(),
            "YDai: Already mature",
        );
    });

    it("yDai chi gets fixed at maturity time", async() => {
        await pot.setChi(chi2, { from: owner });
        
        assert(
            await yDai4.chiGrowth.call(),
            subBN(chi2.toString(), chi1.toString()).toString(),
            "Chi differential should be " + subBN(chi2.toString(), chi1.toString()),
        );
    });

    it("yDai rate gets fixed at maturity time", async() => {
        await vat.fold(WETH, vat.address, subBN(rate2.toString(), rate1.toString()), { from: owner });
        
        assert(
            await yDai4.rateGrowth(),
            subBN(rate2.toString(), rate1.toString()).toString(),
            "Rate differential should be " + subBN(rate2.toString(), rate1.toString()),
        );
    });

    /* it("redeem burns yDai to return dai, pulls dai from Treasury", async() => {
        assert.equal(
            await yDai4.balanceOf(user1),
            daiTokens1.toString(),
            "User1 does not have yDai4",
        );
        assert.equal(
            await dai.balanceOf(user1),
            0,
            "User1 has dai",
        );

        await yDai.approve(yDai4.address, daiTokens1, { from: user1 });
        await yDai.redeem(user1, user1, daiTokens1, { from: user1 });

        assert.equal(
            await dai.balanceOf(user1),
            daiTokens1.toString(),
            "User1 should have dai",
        );
        assert.equal(
            await yDai4.balanceOf(user1),
            0,
            "User1 should not have yDai4",
        );
    });

    describe("once chi increases", () => {
        beforeEach(async() => {
            const chiDifferential  = divRay(chi2, chi1);
            const daiTokens2 = mulRay(daiTokens1, chiDifferential);
            const wethTokens2 = mulRay(wethTokens1, chiDifferential)

            let maturity;

            // Scenario in which the user mints daiTokens2 yDai4, chi increases by a 25%, and user redeems daiTokens1 yDai4
            const daiDebt2 = mulRay(daiDebt1, chiDifferential);
            const savings1 = daiTokens2;
            const savings2 = mulRay(savings1, chiDifferential);
            const yDaiSurplus = subBN(daiTokens2, daiTokens1);
            const savingsSurplus = subBN(savings2, daiTokens2);
            
            await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner }); // Keeping above chi
            await pot.setChi(chi2, { from: owner });

            assert(
                await yDai4.chiGrowth.call(),
                chiDifferential.toString(),
                "chi differential should be " + chiDifferential + ", instead is " + (await yDai4.chiGrowth.call()),
            );
        });

        it("redeem with increased chi returns more dai", async() => {
            // Redeem `daiTokens1` yDai to obtain `daiTokens1` * `chiDifferential`

            await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner }); // Keeping above chi
            await pot.setChi(chi2, { from: owner });

            assert.equal(
                await yDai4.balanceOf(user1),
                daiTokens1.toString(),
                "User1 does not have yDai4",
            );
    
            await yDai4.approve(yDai4.address, daiTokens1, { from: user1 });
            await yDai4.redeem(user1, user1, daiTokens1, { from: user1 });
    
            assert.equal(
                await dai.balanceOf(user1),
                daiTokens2.toString(),
                "User1 should have " + daiTokens2 + " dai, instead has " + (await dai.balanceOf(user1)),
            );
            assert.equal(
                await yDai4.balanceOf(user1),
                0,
                "User2 should have no yDai left, instead has " + (await yDai4.balanceOf(user1)),
            );
        });
    }); */
});