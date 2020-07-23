const ethers = require("ethers");
const toBytes32 = ethers.utils.formatBytes32String;

const Vat = artifacts.require('Vat');
const Jug = artifacts.require('Jug');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const End = artifacts.require('End');
const Chai = artifacts.require('Chai');
const Treasury = artifacts.require('Treasury');
const YDai = artifacts.require('YDai');
const Controller = artifacts.require('Controller');
const Liquidations = artifacts.require('Liquidations');
const Unwind = artifacts.require('Unwind');

const { WETH, CHAI, Line, spotName, linel, limits, spot, rate1, chi1, tag, fix, toRay, addBN, subBN, divRay, mulRay } = require("./utils");

const setupMaker = async() => {
    // Set up vat, join and weth
    vat = await Vat.new();
    await vat.init(WETH); // Set WETH rate to 1.0

    weth = await Weth.new();
    wethJoin = await GemJoin.new(vat.address, WETH, weth.address);

    dai = await ERC20.new(0);
    daiJoin = await DaiJoin.new(vat.address, dai.address);

    // Setup vat
    await vat.file(WETH, spotName, spot);
    await vat.file(WETH, linel, limits);
    await vat.file(Line, limits); 
    await vat.fold(WETH, vat.address, subBN(rate1, toRay(1))); // Fold only the increase from 1.0

    // Setup pot
    pot = await Pot.new(vat.address);
    await pot.setChi(chi1);

    // Setup chai
    chai = await Chai.new(
        vat.address,
        pot.address,
        daiJoin.address,
        dai.address,
    );

    // Setup jug
    jug = await Jug.new(vat.address);
    await jug.init(WETH); // Set WETH duty (stability fee) to 1.0

    // Setup end
    end = await End.new();
    await end.file(toBytes32("vat"), vat.address);

    // Permissions
    await vat.rely(vat.address);
    await vat.rely(wethJoin.address);
    await vat.rely(daiJoin.address);
    await vat.rely(pot.address);
    await vat.rely(jug.address);
    await vat.rely(end.address);

    return {
        vat,
        weth,
        wethJoin,
        dai,
        daiJoin,
        pot,
        jug,
        end,
        chai,
        end,
    }
}

// Helper for deploying Treasury
async function newTreasury() {
    treasury = await Treasury.new(
        vat.address,
        weth.address,
        dai.address,
        wethJoin.address,
        daiJoin.address,
        pot.address,
        chai.address,
    );
    return treasury;
}

// Helper for deploying YDai
async function newYDai(maturity, name, symbol) {
    const yDai = await YDai.new(
        vat.address,
        jug.address,
        pot.address,
        treasury.address,
        maturity,
        name,
        symbol,
    );
    await controller.addSeries(yDai.address);
    await yDai.orchestrate(controller.address);
    await treasury.orchestrate(yDai.address);
    return yDai;
}

// Deploys the controller with 2 Ydai contracts with maturities at 1000 and 
// 2000 blocks from now
async function newController() {
    // Setup Controller
    controller = await Controller.new(
        vat.address,
        pot.address,
        treasury.address,
    );
    await treasury.orchestrate(controller.address);

    return controller;
}

async function newLiquidations() {
    liquidations = await Liquidations.new(
        dai.address,
        treasury.address,
        controller.address,
    );
    await controller.orchestrate(liquidations.address);
    await treasury.orchestrate(liquidations.address);

    return liquidations
}

async function newUnwind() {
    // Setup Unwind
    unwind = await Unwind.new(
        vat.address,
        daiJoin.address,
        weth.address,
        wethJoin.address,
        jug.address,
        pot.address,
        end.address,
        chai.address,
        treasury.address,
        controller.address,
        liquidations.address,
    );
    await treasury.orchestrate(unwind.address);
    await treasury.registerUnwind(unwind.address);
    await controller.orchestrate(unwind.address);
    await liquidations.orchestrate(unwind.address);

    return unwind
}

async function getDai(user, _daiTokens, _rate) {
    await vat.hope(daiJoin.address, { from: user });
    await vat.hope(wethJoin.address, { from: user });

    const _daiDebt = addBN(divRay(_daiTokens, _rate), 1);
    const _wethTokens = divRay(_daiTokens, spot).mul(2);

    await weth.deposit({ from: user, value: _wethTokens });
    await weth.approve(wethJoin.address, _wethTokens, { from: user });
    await wethJoin.join(user, _wethTokens, { from: user });
    await vat.frob(WETH, user, user, user, _wethTokens, _daiDebt, { from: user });
    await daiJoin.exit(user, _daiTokens, { from: user });
}

async function getChai(user, _chaiTokens, _chi, _rate) {
    const _daiTokens = mulRay(_chaiTokens, _chi);
    await getDai(user, _daiTokens, _rate);
    await dai.approve(chai.address, _daiTokens, { from: user });
    await chai.join(user, _daiTokens, { from: user });
}

// Convert eth to weth and post it to yDai
async function postWeth(user, _wethTokens) {
    await weth.deposit({ from: user, value: _wethTokens });
    await weth.approve(treasury.address, _wethTokens, { from: user });
    await controller.post(WETH, user, user, _wethTokens, { from: user });
}

// Convert eth to chai and post it to yDai
async function postChai(user, _chaiTokens, _chi, _rate) {
    await getChai(user, _chaiTokens, _chi, _rate);
    await chai.approve(treasury.address, _chaiTokens, { from: user });
    await controller.post(CHAI, user, user, _chaiTokens, { from: user });
}

async function shutdown(owner, user1, user2) {
    await end.cage();
    await end.setTag(WETH, tag);
    await end.setDebt(1);
    await end.setFix(WETH, fix);
    await end.skim(WETH, user1);
    await end.skim(WETH, user2);
    await end.skim(WETH, owner);
    await unwind.unwind();
    await unwind.settleTreasury();
    await unwind.cashSavings();
}

module.exports = {
    setupMaker,
    newTreasury,
    newYDai,
    newController,
    newLiquidations,
    newUnwind,
    getDai,
    getChai,
    postWeth,
    postChai,
    shutdown,
}
