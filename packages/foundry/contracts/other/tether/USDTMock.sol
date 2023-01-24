// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IUSDT.sol";

abstract contract USDTMock is IUSDT {
    uint public basisPointsRate = 17;
    uint public maximumFee = 13 * 10**6;

    // Ensure transparency by hardcoding limit beyond which fees can never be added
    // require(newBasisPoints < 20);
    // require(newMaxFee < 50);

    // basisPointsRate = newBasisPoints;
    // maximumFee = newMaxFee * 10**6;

}