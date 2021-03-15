// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "./ERC20Mock.sol";


library RMath { // Fixed point arithmetic in Ray units
    /// @dev Multiply an amount by a fixed point factor in ray units, returning an amount
    function rmul(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            uint256 _z = uint256(x) * uint256(y) / 1e27;
            require (_z <= type(uint128).max, "RMUL Overflow");
            z = uint128(_z);
        }
    }

    /// @dev Divide x and y, with y being fixed point. If both are integers, the result is a fixed point factor. Rounds down.
    function rdiv(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            require (y > 0, "RDIV by zero");
            uint256 _z = uint256(x) * 1e27 / y;
            require (_z <= type(uint128).max, "RDIV Overflow");
            z = uint128(_z);
        }
    }
}

contract PoolMock {
    using RMath for uint128;

    IERC20 public baseToken;
    IFYToken public fyToken;
    uint128 constant public rate = 5e25; // 5%

    uint112 public baseTokenReserves;
    uint112 public fyTokenReserves;

    constructor(
        IERC20 baseToken_,
        IFYToken fyToken_
    ) {
        baseToken = baseToken_;
        fyToken = fyToken_;
        _update();
    }

    function _update() internal {
        baseTokenReserves = uint112(baseToken.balanceOf(address(this)));
        fyTokenReserves = uint112(fyToken.balanceOf(address(this)));
    }

    function sellBaseToken(address to, uint128 tokenIn) external returns(uint128) {
        require(
            baseTokenReserves + uint112(tokenIn) >= uint112(baseToken.balanceOf(address(this))),
            "Pool: Not enough base token in"
        );
        fyToken.transfer(to, tokenIn.rmul(rate));
        _update();
        return tokenIn.rmul(rate);
    }
    function buyBaseToken(address to, uint128 tokenOut) external returns(uint128) {
        fyToken.transferFrom(msg.sender, address(this), tokenOut.rmul(rate));
        baseToken.transfer(to, tokenOut);
        _update();
        return tokenOut.rmul(rate);
    }
    function sellFYToken(address to, uint128 fyTokenIn) external returns(uint128) {
        require(
            fyTokenReserves + uint112(fyTokenIn) >= uint112(fyToken.balanceOf(address(this))),
            "Pool: Not enough fyToken in"
        );
        baseToken.transfer(to, fyTokenIn.rdiv(rate));
        _update();
        return fyTokenIn.rdiv(rate);
    }
    function buyFYToken(address to, uint128 fyTokenOut) external returns(uint128) {
        baseToken.transferFrom(msg.sender, address(this), fyTokenOut.rdiv(rate));
        fyToken.transfer(to, fyTokenOut);
        _update();
        return fyTokenOut.rdiv(rate);
    }
}
