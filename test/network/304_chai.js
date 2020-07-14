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
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');

contract('Chai', async (accounts) =>  {
    const [ owner, user ] = accounts;

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
    const chi = toRay(1.2); // TODO: Set it up in migrations

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

        spot  = (await vat.ilks(WETH)).spot;
        rate  = (await vat.ilks(WETH)).rate;
        wethTokens = toWad(1);
        daiTokens = mulRay(wethTokens.toString(), spot.toString());
        daiDebt = divRay(daiTokens.toString(), rate.toString());

        await pot.setChi(chi); // TODO: Set it up in migrations
        chaiTokens = divRay(daiTokens, chi);
    });

    it("allows to exchange dai for chai", async() => {
        // Borrow some dai
        await vat.hope(daiJoin.address, { from: user }); // `user` allowing daiJoin to move his dai.
        await vat.hope(wethJoin.address, { from: user }); // `user` allowing wethJoin to move his weth.
        await weth.deposit({ from: user, value: wethTokens});
        await weth.approve(wethJoin.address, wethTokens, { from: user }); 
        await wethJoin.join(user, wethTokens, { from: user });
        await vat.frob(WETH, user, user, user, wethTokens, daiDebt, { from: user });
        await daiJoin.exit(user, daiTokens, { from: user });

        // Convert dai to chai
        await dai.approve(chai.address, daiTokens, { from: user }); 
        await chai.join(user, daiTokens, { from: user });
        
        assert.equal(
            await chai.balanceOf(user),   
            chaiTokens.toString(),
            "Should have chai",
        );
        assert.equal(
            await dai.balanceOf(user),   
            0,
            "Should not have dai",
        );
    });

    it("allows to exchange chai for dai", async() => {
        // Convert chai to dai
        await chai.exit(user, chaiTokens, { from: user });

        // Test transfer of chai
        assert.equal(
            await dai.balanceOf(user),   
            daiTokens.toString(),
            "Should have dai",
        );
        assert.equal(
            await chai.balanceOf(user),   
            0,
            "Should not have chai",
        );

        // Repay the dai
        await dai.approve(daiJoin.address, daiTokens, { from: user }); 
        await daiJoin.join(user, daiTokens, { from: user });
        await vat.frob(WETH, user, user, user, wethTokens.mul(-1), daiDebt.mul(-1), { from: user });
        await wethJoin.exit(user, wethTokens, { from: user });
        await weth.withdraw(wethTokens, { from: user });
    });
});