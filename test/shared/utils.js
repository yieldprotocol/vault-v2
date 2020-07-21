const ethers = require("ethers");
const toBytes32 = ethers.utils.formatBytes32String;
const bigNumberify = ethers.utils.bigNumberify;

// Helper functions

// Convert eth to weth and use it to borrow `daiTokens` from MakerDAO
// This function shadows and uses global variables, careful.
async function getDai(user, _daiTokens){
    await vat.hope(daiJoin.address, { from: user });
    await vat.hope(wethJoin.address, { from: user });

    const _daiDebt = divRay(_daiTokens, rate);
    const _wethTokens = addBN(divRay(_daiTokens, spot), 1);

    await weth.deposit({ from: user, value: _wethTokens });
    await weth.approve(wethJoin.address, _wethTokens, { from: user });
    await wethJoin.join(user, _wethTokens, { from: user });
    await vat.frob(WETH, user, user, user, _wethTokens, _daiDebt, { from: user });
    await daiJoin.exit(user, _daiTokens, { from: user });
}


/// @dev Converts a number to WAD precision, for number up to 10 decimal places
const toWad = function(value) {
    let exponent = bigNumberify('10').pow(bigNumberify('8'));
    return bigNumberify(value*10**10).mul(exponent);
}

/// @dev Converts a number to RAY precision, for number up to 10 decimal places
const toRay = function(value) {
    let exponent = bigNumberify('10').pow(bigNumberify('17'));
    return bigNumberify(value*10**10).mul(exponent);
}

/// @dev Converts a number to RAD precision, for number up to 10 decimal places
const toRad = function(value) {
    let exponent = bigNumberify('10').pow(bigNumberify('35'));
    return bigNumberify(value*10**10).mul(exponent);
}

/// @dev Adds two numbers
/// I.e. addBN(ray(x), ray(y)) = ray(x - y)
const addBN = function(x, y) {
    return bigNumberify(x).add(bigNumberify(y));
}

/// @dev Substracts a number from another
/// I.e. subBN(ray(x), ray(y)) = ray(x - y)
const subBN = function(x, y) {
    return bigNumberify(x).sub(bigNumberify(y));
}

/// @dev Multiplies a number in any precision by a number in RAY precision, with the output in the first parameter's precision.
/// I.e. mulRay(wad(x), ray(y)) = wad(x*y)
const mulRay = function(x, ray) {
    let unit = bigNumberify('10').pow(bigNumberify('27'));
    return bigNumberify(x).mul(bigNumberify(ray)).div(unit);
}

/// @dev Divides a number in any precision by a number in RAY precision, with the output in the first parameter's precision.
/// I.e. divRay(wad(x), ray(y)) = wad(x/y)
const divRay = function(x, ray) {
    let unit = bigNumberify('10').pow(bigNumberify('27'));
    return unit.mul(bigNumberify(x)).div(bigNumberify(ray));
}

// Constants
const WETH = toBytes32("ETH-A");
const Line = toBytes32("Line");
const spotName = toBytes32("spot");
const linel = toBytes32("line");

const limits =  toRad(10000);
const spot = toRay(1.5);
const chi = toRay(1.2);
const rate = toRay(1.4); // TODO: If this is changed to 1.2, the `redeem with increased chi returns more dai` test fails

const daiDebt = toWad(120);
const daiTokens = mulRay(daiDebt, rate);
const wethTokens = divRay(daiTokens, spot);
const chaiTokens = divRay(daiTokens, chi);


module.exports = {
    getDai,
    toWad,
    toRay,
    toRad,
    addBN,
    subBN,
    mulRay,
    divRay,

    // constants
    WETH,
    Line,
    spotName,
    linel,
    limits,
    spot,
    rate,
    chi,
    daiDebt,
    daiTokens,
    wethTokens,
    chaiTokens,
}
