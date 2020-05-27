const ethers = require("ethers");
const bigNumberify = ethers.utils.bigNumberify;

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

module.exports = {
    toRay,
    toRad
}