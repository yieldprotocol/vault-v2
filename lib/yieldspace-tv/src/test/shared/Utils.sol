// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;

import {console} from "forge-std/console.sol";
import {IERC4626Mock} from "../mocks/ERC4626TokenMock.sol";
import "../../Math64x64.sol";

function mulMu(uint256 amount, int128 mu_) pure returns (uint256 product) {
    product = (amount * Math64x64.toUInt(Math64x64.mul(mu_, Math64x64.fromUInt(uint256(1e18))))) / 1e18;
}

function almostEqual(
    uint256 x,
    uint256 y,
    uint256 p
) view {
    uint256 diff = x > y ? x - y : y - x;
    if (diff / p != 0) {
        console.log(x);
        console.log("is not almost equal to");
        console.log(y);
        console.log("with p of:");
        console.log(p);
        revert();
    }
}

function setPrice(address token, uint256 price) {
    // setPrice() appears on ERC4626TokenMock and other mocks
    // so this fn can be used to set price on either
    IERC4626Mock(token).setPrice(price);
}
