const ethers = require("ethers");
const bigNumberify = ethers.utils.bigNumberify;


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

module.exports = {
    toWad,
    toRay,
    toRad,
    addBN,
    subBN,
    mulRay,
    divRay
}