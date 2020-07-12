const Migrations = artifacts.require('Migrations');
const Vat = artifacts.require("Vat");
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const GemJoin = artifacts.require("GemJoin");
const DaiJoin = artifacts.require("DaiJoin");
const Jug = artifacts.require("Jug");
const Pot = artifacts.require("Pot");
const Chai = artifacts.require("Chai");
const GasToken = artifacts.require("GasToken1");
const Treasury = artifacts.require("Treasury");
const Controller = artifacts.require("Controller");

const truffleAssert = require('truffle-assertions');
const { expectRevert } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');

contract('Treasury - Saving', async (accounts) =>  {
    let [ owner, user ] = accounts;

    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let jug;
    let pot;
    let chai;
    let gasToken;
    let treasury;
    let controller;

    let WETH = web3.utils.fromAscii('ETH-A');
    let spot;
    let rate;
    let chi;
    
    let wethTokens;
    let daiTokens;
    let daiDebt;
    let chaiTokens;

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
        rate  = (await vat.ilks(WETH)).rate;
        chi = await pot.chi(); // Good boys call drip()

        wethTokens = toWad(1);
        daiTokens = mulRay(wethTokens.toString(), spot.toString());
        daiDebt = divRay(daiTokens.toString(), rate.toString());
        chaiTokens = divRay(daiTokens, chi.toString());
        
        await treasury.orchestrate(owner, { from: owner });
        await vat.hope(daiJoin.address, { from: owner });
    });

    it("allows to save dai", async() => {
        // Borrow some dai
        await weth.deposit({ from: owner, value: wethTokens});
        await weth.approve(wethJoin.address, wethTokens, { from: owner }); 
        await wethJoin.join(owner, wethTokens, { from: owner });
        await vat.frob(WETH, owner, owner, owner, wethTokens, daiDebt, { from: owner });
        await daiJoin.exit(owner, daiTokens, { from: owner });
        
        await dai.approve(treasury.address, daiTokens, { from: owner }); 
        await treasury.pushDai(owner, daiTokens, { from: owner });

        // Test transfer of collateral
        assert.equal(
            await chai.balanceOf(treasury.address),
            chaiTokens.toString(),
            "Treasury should have chai"
        );
        assert.equal(
            await treasury.savings.call(),
            daiTokens.toString(),
            "Treasury should have " + daiTokens + " savings in dai units, instead has " + await treasury.savings.call(),
        );
        assert.equal(
            await dai.balanceOf(owner),
            0,
            "User should not have dai",
        );
    });

    it("pulls dai from savings", async() => {
        await treasury.pullDai(owner, daiTokens, { from: owner });

        assert.equal(
            await chai.balanceOf(treasury.address),
            0,
            "Treasury should not have chai",
        );
        assert.equal(
            await treasury.savings.call(),
            0,
            "Treasury should not have savings in dai units"
        );
        assert.equal(
            await dai.balanceOf(owner),
            daiTokens.toString(),
            "User should have dai",
        );
    });

    it("allows to save chai", async() => {
        await dai.approve(chai.address, daiTokens, { from: owner });
        await chai.join(owner, daiTokens, { from: owner });
        await chai.approve(treasury.address, chaiTokens, { from: owner }); 
        await treasury.pushChai(owner, chaiTokens, { from: owner });

        // Test transfer of collateral
        assert.equal(
            await chai.balanceOf(treasury.address),
            chaiTokens.toString(),
            "Treasury should have chai"
        );
        assert.equal(
            await treasury.savings.call(),
            daiTokens.toString(),
            "Treasury should report savings in dai units"
        );
        assert.equal(
            await chai.balanceOf(owner),
            0,
            "User should not have chai",
        );
    });

    it("pulls chai from savings", async() => {
        await treasury.pullChai(owner, chaiTokens, { from: owner });

        assert.equal(
            await chai.balanceOf(treasury.address),
            0,
            "Treasury should not have chai",
        );
        assert.equal(
            await treasury.savings.call(),
            0,
            "Treasury should not have savings in dai units"
        );
        assert.equal(
            await chai.balanceOf(owner),
            chaiTokens.toString(),
            "User should have chai",
        );

        // Exchange the chai back
        await chai.exit(owner, chaiTokens, { from: owner });

        // Repay the dai
        await dai.approve(daiJoin.address, daiTokens, { from: owner }); 
        await daiJoin.join(owner, daiTokens, { from: owner });
        await vat.frob(WETH, owner, owner, owner, wethTokens.mul(-1), daiDebt.mul(-1), { from: owner });
        await wethJoin.exit(owner, wethTokens, { from: owner });

        // Withdraw the eth
        await weth.withdraw(wethTokens, { from: owner });
    });
});