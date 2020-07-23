import { formatBytes32String as toBytes32 } from "ethers/lib/utils";
import { BigNumber, Contract } from "ethers";

// TODO: Replace these with buidler-style JSON imports & `waffle.deployContract`
// once we move away from Truffle testing

// @ts-ignore
const Vat = artifacts.require('Vat');
// @ts-ignore
const Jug = artifacts.require('Jug');
// @ts-ignore
const GemJoin = artifacts.require('GemJoin');
// @ts-ignore
const DaiJoin = artifacts.require('DaiJoin');
// @ts-ignore
const Weth = artifacts.require("WETH9");
// @ts-ignore
const ERC20 = artifacts.require("TestERC20");
// @ts-ignore
const Pot = artifacts.require('Pot');
// @ts-ignore
const End = artifacts.require('End');
// @ts-ignore
const Chai = artifacts.require('Chai');
// @ts-ignore
const Treasury = artifacts.require('Treasury');
// @ts-ignore
const YDai = artifacts.require('YDai');
// @ts-ignore
const Controller = artifacts.require('Controller');
// @ts-ignore
const Liquidations = artifacts.require('Liquidations');
// @ts-ignore
const Unwind = artifacts.require('Unwind');

import { WETH, CHAI, Line, spotName, linel, limits, spot, rate1, chi1, tag, fix, toRay, addBN, subBN, divRay, mulRay } from "./utils";

declare global {
   var vat: Contract;
   var weth: Contract;
   var wethJoin: Contract;
   var dai: Contract;
   var daiJoin: Contract;
   var chai: Contract;
   var pot: Contract;
   var treasury: Contract;
   var controller: Contract;
   var jug: Contract;
   var end: Contract;
   var liquidations: Contract;
   var unwind: Contract;
   var yDai1: Contract;
   var yDai1: Contract;
}

const setupMaker = async() => {
    // Set up vat, join and weth
    globalThis.vat = await Vat.new();
    await vat.init(WETH); // Set WETH rate to 1.0

    globalThis.weth = await Weth.new();
    globalThis.wethJoin = await GemJoin.new(vat.address, WETH, weth.address);

    globalThis.dai = await ERC20.new(0);
    globalThis.daiJoin = await DaiJoin.new(vat.address, dai.address);

    // Setup vat
    await vat.file(WETH, spotName, spot);
    await vat.file(WETH, linel, limits);
    await vat.file(Line, limits); 
    await vat.fold(WETH, vat.address, subBN(rate1, toRay(1))); // Fold only the increase from 1.0

    // Setup pot
    globalThis.pot = await Pot.new(vat.address);
    await pot.setChi(chi1);

    // Setup chai
    globalThis.chai = await Chai.new(
        vat.address,
        pot.address,
        daiJoin.address,
        dai.address,
    );

    // Setup jug
    globalThis.jug = await Jug.new(vat.address);
    await jug.init(WETH); // Set WETH duty (stability fee) to 1.0

    // Setup end
    globalThis.end = await End.new();
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
    }
}

// Helper for deploying Treasury
async function newTreasury() {
    globalThis.treasury = await Treasury.new(
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
async function newYDai(maturity: number, name: string, symbol: string) {
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
    globalThis.controller = await Controller.new(
        vat.address,
        pot.address,
        treasury.address,
    );
    await treasury.orchestrate(controller.address);

    return controller;
}

async function newLiquidations() {
    globalThis.liquidations = await Liquidations.new(
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
    globalThis.unwind = await Unwind.new(
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

async function getDai(user: string, _daiTokens: BigNumber, _rate: number) {
    await vat.hope(daiJoin.address, { from: user });
    await vat.hope(wethJoin.address, { from: user });

    const _daiDebt = addBN(divRay(_daiTokens, _rate), 1).toString();
    const _wethTokens = divRay(_daiTokens, spot).mul(2).toString();

    await weth.deposit({ from: user, value: _wethTokens });
    await weth.approve(wethJoin.address, _wethTokens, { from: user });
    await wethJoin.join(user, _wethTokens, { from: user });
    await vat.frob(WETH, user, user, user, _wethTokens, _daiDebt, { from: user });
    await daiJoin.exit(user, _daiTokens, { from: user });
}

async function getChai(user: string, _chaiTokens: number, _chi: number, _rate: number) {
    const _daiTokens = mulRay(_chaiTokens, _chi);
    await getDai(user, _daiTokens, _rate);
    await dai.approve(chai.address, _daiTokens, { from: user });
    await chai.join(user, _daiTokens, { from: user });
}

// Convert eth to weth and post it to yDai
async function postWeth(user: string, _wethTokens: number) {
    await weth.deposit({ from: user, value: _wethTokens.toString() });
    await weth.approve(treasury.address, _wethTokens, { from: user });
    await controller.post(WETH, user, user, _wethTokens, { from: user });
}

// Convert eth to chai and post it to yDai
async function postChai(user: string, _chaiTokens: number, _chi: number, _rate: number) {
    await getChai(user, _chaiTokens, _chi, _rate);
    await chai.approve(treasury.address, _chaiTokens, { from: user });
    await controller.post(CHAI, user, user, _chaiTokens, { from: user });
}

async function shutdown(owner: string, user1: string, user2: string) {
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
