const Migrations = artifacts.require('Migrations');
const Vat = artifacts.require("Vat");
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const GemJoin = artifacts.require("GemJoin");
const DaiJoin = artifacts.require("DaiJoin");
const Jug = artifacts.require("Jug");
const Pot = artifacts.require("Pot");
const Chai = artifacts.require("Chai");
const Treasury = artifacts.require("Treasury");
const Controller = artifacts.require("Controller");

const { expectRevert } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');

contract('Vat', async (accounts, network) =>  {
    const [ owner, user ] = accounts;

    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let jug;
    let pot;
    let chai;
    let treasury;
    let controller;

    let WETH = web3.utils.fromAscii('ETH-A');
    let spot;
    let rate;
    let wethTokens;
    let daiTokens;
    let daiDebt;

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

        spot  = (await vat.ilks(WETH)).spot;
        rate  = (await vat.ilks(WETH)).rate;
        wethTokens = toWad(1);
        daiTokens = mulRay(wethTokens.toString(), spot.toString());
        daiDebt = divRay(daiTokens.toString(), rate.toString());

        await vat.hope(daiJoin.address, { from: user }); // `user` allowing daiJoin to move his dai.
    });

    it('should setup vat', async() => {
        console.log("    Limits: " + await vat.Line());
        console.log("    Spot: " + (await vat.ilks(WETH)).spot);
        console.log("    Rate: " + (await vat.ilks(WETH)).rate);
    });

    it('should deposit collateral', async() => {
        assert.equal(
            await weth.balanceOf(wethJoin.address),   
            0,
        );

        await weth.deposit({ from: user, value: wethTokens });
        await weth.approve(wethJoin.address, wethTokens, { from: user }); 
        await wethJoin.join(user, wethTokens, { from: user });

        assert.equal(
            await weth.balanceOf(wethJoin.address),   
            wethTokens.toString(),
            'User should have joined ' + wethTokens + ' weth.'
        );

        await vat.frob(WETH, user, user, user, wethTokens, 0, { from: user });
        
        assert.equal(
            (await vat.urns(WETH, user)).ink,   
            wethTokens.toString(),
            'User should have ' + wethTokens + ' weth as collateral.',
        );
    });

    it('should borrow Dai', async() => {
        await vat.frob(WETH, user, user, user, 0, daiDebt, { from: user });

        assert.equal(
            (await vat.urns(WETH, user)).art,   
            daiDebt.toString(),
            'User should have ' + daiDebt + ' dai debt.',
        );

        await daiJoin.exit(user, daiTokens, { from: user });

        assert.equal(
            await dai.balanceOf(user),   
            daiTokens.toString(),
            'User should have ' + daiTokens + ' dai.',
        );
    });

    it('should repay Dai', async() => {
        await daiJoin.join(user, daiTokens, { from: user });
        assert.equal(
            await dai.balanceOf(user),   
            0,
            'User should have no dai.',
        );

        await vat.frob(WETH, user, user, user, 0, daiDebt.mul(-1), { from: user });

        assert.equal(
            (await vat.urns(WETH, user)).art,   
            0,
            'Owner should have no dai debt.',
        );
    });

    it('should withdraw collateral', async() => {
        await vat.frob(WETH, user, user, user, wethTokens.mul(-1), 0, { from: user });

        assert.equal(
            (await vat.urns(WETH, user)).ink,   
            0,
            'User should have no weth as collateral.',
        );

        await wethJoin.exit(user, wethTokens, { from: user });

        assert.equal(
            await weth.balanceOf(user),   
            wethTokens.toString(),
            'User should have ' + wethTokens + ' weth.',
        );

        await weth.withdraw(wethTokens, { from: user });
    });
});