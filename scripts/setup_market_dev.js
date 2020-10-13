const { id } = require('ethers/lib/utils')
const { BigNumber } = require("ethers");

// External
const Migrations = artifacts.require('Migrations');
const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const Dai = artifacts.require("Dai");

// FYDai
const FYDai = artifacts.require('FYDai');

// Peripheral
const Pool = artifacts.require('Pool');

// Maths brought in cos
const UNIT = BigNumber.from(10).pow(BigNumber.from(27))
function toRay(value) {
    let exponent = BigNumber.from(10).pow(BigNumber.from(17))
    return BigNumber.from((value) * 10 ** 10).mul(exponent)
  }
function toWad(value){
    let exponent = BigNumber.from(10).pow(BigNumber.from(8))
    return BigNumber.from((value) * 10 ** 10).mul(exponent)
}
function mulRay(x, ray){
    return BigNumber.from(x).mul(BigNumber.from(ray)).div(UNIT)
  }
function divRay(x, ray){
    console.log(x,ray)
    return UNIT.mul(BigNumber.from(x)).div(BigNumber.from(ray))
}

module.exports = async (callback) => {

    let [ owner, user1 ] = await web3.eth.getAccounts()
    const migrations = await Migrations.deployed();

    let vat = await Vat.deployed()
    let weth = await Weth.deployed()
    let wethJoin= await GemJoin.deployed();
    let dai = await Dai.deployed();
    let daiJoin = await DaiJoin.deployed();

    let WETH = web3.utils.fromAscii("ETH-A");

    let spot = toRay(150);
    let rate1 = toRay(1.25);

    const daiDebt1 = toWad(90);
    const daiTokens1 = mulRay(daiDebt1, rate1);

    // Convert eth to weth and use it to borrow `daiTokens` from MakerDAO
    // This function shadows and uses global variables, careful.
    async function getDai(user, _daiTokens){

        await vat.hope(daiJoin.address, { from: user });
        await vat.hope(wethJoin.address, { from: user });

        const _daiDebt = divRay(_daiTokens, rate1);
        const _wethTokens = divRay(_daiTokens, spot);

        await weth.deposit({ from: user, value: _wethTokens.toString() });
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

    let fyDaiAddr = await migrations.contracts(web3.utils.fromAscii(`fyDai0`))
    let fyDai0 = await FYDai.at(fyDaiAddr);
    let fyDai0Name = await fyDai0.name();
    let poolAddr = await migrations.contracts(web3.utils.fromAscii(`${fyDai0Name}-Pool`));
    let pool = await Pool.at(poolAddr);

    try {        
        // Allow owner to mint fyDai the sneaky way, without recording a debt in dealer
        await fyDai0.orchestrate(owner, id('mint(address,uint256)'), { from: owner });

        const daiReserves = daiTokens1;
        await getDai(user1, daiReserves);       console.log('0')
        await dai.approve(pool.address, daiReserves, { from: user1 });       console.log('1')
        await pool.mint(user1, user1, daiReserves, { from: user1 });     console.log('2')

        const additionalFYDaiReserves = toWad(34.4);
        await fyDai0.mint(user1, additionalFYDaiReserves, { from: owner });
        await fyDai0.approve(pool.address, additionalFYDaiReserves, { from: user1 });
        await pool.sellFYDai(user1, user1, additionalFYDaiReserves, { from: user1 });

        console.log("        initial liquidity...");
        console.log("        daiReserves: %d", (await pool.getDaiReserves()).toString());
        console.log("        fyDaiReserves: %d", (await pool.getFYDaiReserves()).toString());
        console.log();
        console.log('pool initiated')
        callback()
    } catch (e) {console.log(e)}

}
