const { BN } = require('@openzeppelin/test-helpers');

// External
const Migrations = artifacts.require('Migrations');
const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Chai = artifacts.require('Chai');

// YDai
const YDai = artifacts.require('YDai');

// Peripheral
const Market = artifacts.require('Market');

module.exports = async (callback) => {

    const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('../test/shared/utils');

    // const { assert, expect } = require('chai');
    let [ owner, user1, operator, from, to ] = await web3.eth.getAccounts()
    const migrations = await Migrations.deployed();

    let seriesNames = ['yDai1', 'yDai2', 'yDai3', 'yDai4'];

    let vat = await Vat.deployed()
    let weth = await Weth.deployed()
    let wethJoin= await GemJoin.deployed();
    let dai = await ERC20.deployed();
    let daiJoin = await DaiJoin.deployed();

    let ilk = web3.utils.fromAscii("ETH-A");
    let Line = web3.utils.fromAscii("Line");
    let spotName = web3.utils.fromAscii("spot");
    let linel = web3.utils.fromAscii("line");

    const limits =  toRad(10000);

    let ilks = await vat.ilks(web3.utils.fromAscii('ETH-A'))
    console.log(ilks.spot.toString())
    console.log(ilks.rate.toString())

    let spot = toRay(150);
    let rate1 = toRay(1.25);

    const chi1 = toRay(1.2);
    const rate2 = toRay(1.82);
    const chi2 = toRay(1.5);

    const chiDifferential  = divRay(chi2, chi1);

    const daiDebt1 = toWad(90);
    const daiTokens1 = mulRay(daiDebt1, rate1);
    const yDaiTokens1 = daiTokens1;
    const wethTokens1 = divRay(daiTokens1, spot);

    let maturity;

    // Convert eth to weth and use it to borrow `daiTokens` from MakerDAO
    // This function shadows and uses global variables, careful.
    async function getDai(user, _daiTokens){

        await vat.hope(daiJoin.address, { from: user });
        await vat.hope(wethJoin.address, { from: user });

        const _daiDebt = divRay(_daiTokens, rate1);
        const _wethTokens = divRay(_daiTokens, spot);

        await weth.deposit({ from: user, value: _wethTokens });
        console.log('Passed deposit');
        await weth.approve(wethJoin.address, _wethTokens, { from: user });
        console.log('Passed approve');
        await wethJoin.join(user, _wethTokens, { from: user });
        console.log('Passed WethJoin');
        await vat.frob(ilk, user, user, user, _wethTokens, _daiDebt, { from: user });
        console.log('Passed Frob');
        await daiJoin.exit(user, _daiTokens, { from: user });
        console.log('Passed Daijoin exit');
    }

    // Increase the rate accumulator
    // await vat.fold(ilk, vat.address, subBN(rate1, toRay(1)), { from: owner }); // Fold only the increase from 1.0
    // await pot.setChi(chi1, { from: owner }); // Set the savings accumulator

    let yDaiAddr = await migrations.contracts(web3.utils.fromAscii(`yDai1`))
    let yDai1 = await YDai.at(yDaiAddr);
    let marketAddr = await migrations.contracts(web3.utils.fromAscii(`Market-yDai1`));
    let market = await Market.at(marketAddr);

    try { 
        // Allow owner to mint yDai the sneaky way, without recording a debt in dealer
        await yDai1.orchestrate(owner, { from: owner });

        const daiReserves = daiTokens1;
        const yDaiReserves = yDaiTokens1.mul(2);
        await getDai(user1, daiReserves)
        await yDai1.mint(user1, yDaiReserves, { from: owner });
        console.log("        initial liquidity...");
        console.log("        daiReserves: %d", daiReserves.toString());
        console.log("        yDaiReserves: %d", yDaiReserves.toString());
        const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp);
        console.log("        timeTillMaturity: %d", (new BN(maturity).sub(t).toString()));
        await dai.approve(market.address, daiReserves, { from: user1 });
        await yDai1.approve(market.address, yDaiReserves, { from: user1 });
        console.log();
        console.log();
        await market.init(daiReserves, yDaiReserves, { from: user1 });
        console.log('market initiated')
        callback()
    } catch (e) {console.log(e)}

}


