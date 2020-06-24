const Vat = artifacts.require("Vat");
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const GemJoin = artifacts.require("GemJoin");
const DaiJoin = artifacts.require("DaiJoin");
const Jug = artifacts.require("Jug");
const Pot = artifacts.require("Pot");
const Chai = artifacts.require("Chai");
const GasToken = artifacts.require("GasToken1");
const WethOracle = artifacts.require("WethOracle");
const ChaiOracle = artifacts.require("ChaiOracle");
const Treasury = artifacts.require("Treasury");
const Dealer = artifacts.require("Dealer");

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { expectRevert } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../shared/utils');

contract('Treasury - Lending', async (accounts) =>  {
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
    let wethOracle;
    let chaiOracle;
    let treasury;
    let dealer;

    let ilk = web3.utils.fromAscii('ETH-A');
    let spot;
    let rate;
    const chi = toRay(1.2); // TODO: Set it up in migrations
    
    let wethTokens;
    let daiTokens;
    let daiDebt;
    let chaiTokens;

    beforeEach(async() => {
        vat = await Vat.deployed();
        weth = await Weth.deployed();
        wethJoin = await GemJoin.deployed();
        dai = await ERC20.deployed();
        daiJoin = await DaiJoin.deployed();
        jug = await Jug.deployed();
        pot = await Pot.deployed();
        chai = await Chai.deployed();
        gasToken = await GasToken.deployed();

        spot  = (await vat.ilks(ilk)).spot;
        rate  = (await vat.ilks(ilk)).rate;
        wethTokens = toWad(1);
        daiTokens = mulRay(wethTokens.toString(), spot.toString());
        daiDebt = divRay(daiTokens.toString(), rate.toString());

        await pot.setChi(chi); // TODO: Set it up in migrations
        chaiTokens = divRay(daiTokens, chi);

        // Setup chaiOracle
        chaiOracle = await ChaiOracle.deployed();

        // Permissions

        // Set chi
        await pot.setChi(chi, { from: owner });
        
        treasury = await Treasury.deployed();
        await treasury.grantAccess(owner, { from: owner });
        await vat.hope(daiJoin.address, { from: owner });
    });

    it("allows to post collateral", async() => {
        assert.equal(
            (await weth.balanceOf(wethJoin.address)),
            web3.utils.toWei("0")
        );
        
        await weth.deposit({ from: user, value: wethTokens});
        await weth.transfer(treasury.address, wethTokens, { from: user }); 
        await treasury.pushWeth({ from: owner });

        // Test transfer of collateral
        assert.equal(
            await weth.balanceOf(wethJoin.address),
            wethTokens.toString(),
        );

        // Test collateral registering via `frob`
        assert.equal(
            (await vat.urns(ilk, treasury.address)).ink,
            wethTokens.toString(),
        );
    });

    it("pulls dai borrowed from MakerDAO for user", async() => {
        // Test with two different stability rates, if possible.
        await treasury.pullDai(user, daiTokens, { from: owner });

        assert.equal(
            await dai.balanceOf(user),
            daiTokens.toString(),
        );
        assert.equal(
            (await vat.urns(ilk, treasury.address)).art,
            daiDebt.toString(),
        );
    });

    it("pushes dai that repays debt towards MakerDAO", async() => {
        // Test `normalizedAmount >= normalizedDebt`
        //await dai.approve(treasury.address, daiTokens, { from: user });
        dai.transfer(treasury.address, daiTokens, { from: user }); // We can't stop donations
        await treasury.pushDai({ from: owner });

        assert.equal(
            await dai.balanceOf(user),
            0
        );
        assert.equal(
            (await vat.urns(ilk, treasury.address)).art,
            0,
        );
        assert.equal(
            await vat.dai(treasury.address),
            0
        );
    });

    it("pulls chai converted from dai borrowed from MakerDAO for user", async() => {
        await treasury.pullChai(user, chaiTokens, { from: owner });

        assert.equal(
            await chai.balanceOf(user),
            chaiTokens.toString(),
        );
        assert.equal(
            (await vat.urns(ilk, treasury.address)).art,
            daiDebt.toString(),
        );
    });

    it("pushes chai that repays debt towards MakerDAO", async() => {
        await chai.transfer(treasury.address, chaiTokens, { from: user }); 
        await treasury.pushChai({ from: owner });

        assert.equal(
            await dai.balanceOf(user),
            0
        );
        assert.equal(
            (await vat.urns(ilk, treasury.address)).art,
            0,
        );
        assert.equal(
            await vat.dai(treasury.address),
            0
        );
    });

    it("allows to withdraw collateral", async() => {
        assert.equal(
            await weth.balanceOf(owner),
            0,
        );
        
        await treasury.pullWeth(owner, wethTokens, { from: owner });

        // Test transfer of collateral
        assert.equal(
            (await weth.balanceOf(owner)),
            wethTokens.toString(),
        );

        // Test collateral registering via `frob`
        assert.equal(
            (await vat.urns(ilk, treasury.address)).ink,
            0
        );

        // Restore state
        await weth.withdraw(wethTokens, { from: owner });
    });
});