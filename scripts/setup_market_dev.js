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

    let vat = await Vat.deployed()
    let weth = await Weth.deployed()
    let wethJoin= await GemJoin.deployed();
    let dai = await ERC20.deployed();
    let daiJoin = await DaiJoin.deployed();

    let WETH = web3.utils.fromAscii("ETH-A");

    // let ilks = await vat.ilks(web3.utils.fromAscii(WETH))
    // let spot = ilks.spot;
    // let rate1 = ilks.rate;
    // console.log(ilks.spot.toString())
    // console.log(ilks.rate.toString())

    let spot = toRay(150);
    let rate1 = toRay(1.25);

    const daiDebt1 = toWad(90);
    const daiTokens1 = mulRay(daiDebt1, rate1);
    const yDaiTokens1 = daiTokens1;

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
        await vat.frob(WETH, user, user, user, _wethTokens, _daiDebt, { from: user });
        console.log('Passed Frob');
        await daiJoin.exit(user, _daiTokens, { from: user });
        console.log('Passed Daijoin exit');
    }

    let yDaiAddr = await migrations.contracts(web3.utils.fromAscii(`yDai0`))
    let yDai0 = await YDai.at(yDaiAddr);
    let marketAddr = await migrations.contracts(web3.utils.fromAscii(`Market-yDai0`));
    let market = await Market.at(marketAddr);
    let maturity = await yDai0.maturity();

    try { 
        // Allow owner to mint yDai the sneaky way, without recording a debt in dealer
        await yDai0.orchestrate(owner, { from: owner });

        const daiReserves = daiTokens1;
        await getDai(user1, daiReserves);
    
        await dai.approve(market.address, daiReserves, { from: user1 });
        await market.init(daiReserves, { from: user1 });

        const additionalYDaiReserves = toWad(34.4);
        await yDai0.mint(user1, additionalYDaiReserves, { from: owner });
        await yDai0.approve(market.address, additionalYDaiReserves, { from: user1 });
        await market.sellYDai(user1, user1, additionalYDaiReserves, { from: user1 });

        console.log("        initial liquidity...");
        console.log("        daiReserves: %d", (await market.getDaiReserves()).toString());
        console.log("        yDaiReserves: %d", (await market.getYDaiReserves()).toString());
        const t = new BN((await web3.eth.getBlock(await web3.eth.getBlockNumber())).timestamp);
        console.log("        timeTillMaturity: %d", (new BN(maturity).sub(t).toString()));
        console.log();
        console.log('market initiated')
        callback()
    } catch (e) {console.log(e)}

}


