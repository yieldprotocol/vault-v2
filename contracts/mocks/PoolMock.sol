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
    uint128 constant public rate = 105e25; // 5%

    uint112 public baseTokenReserves;
    uint112 public fyTokenReserves;

    constructor(
        IERC20 baseToken_,
        IFYToken fyToken_
    ) {
        baseToken = baseToken_;
        fyToken = fyToken_;
    }

    function sync() public {
        (baseTokenReserves, fyTokenReserves) = (uint112(baseToken.balanceOf(address(this))), uint112(fyToken.balanceOf(address(this))));
    }

    function update(uint112 baseTokenReserves_, uint112 fyTokenReserves_) public {
        baseTokenReserves = baseTokenReserves_;
        fyTokenReserves = fyTokenReserves_;
    }

    function getBaseTokenReserves() public view returns(uint128) {
        return uint128(baseToken.balanceOf(address(this)));
    }

    function getFYTokenReserves() public view returns(uint128) {
        return uint128(fyToken.balanceOf(address(this)));
    }

    function retrieveBaseToken(address to)
        external
        returns(uint128 surplus)
    {
        surplus = getBaseTokenReserves() - baseTokenReserves; // TODO: Consider adding a require for UX
        require(
            baseToken.transfer(to, surplus),
            "Pool: Base transfer failed"
        );
    }

    function retrieveFYToken(address to)
        external
        returns(uint128 surplus)
    {
        surplus = getFYTokenReserves() - fyTokenReserves; // TODO: Consider adding a require for UX
        require(
            fyToken.transfer(to, surplus),
            "Pool: FYToken transfer failed"
        );
    }

    function sellBaseToken(address to, uint128 min) external returns(uint128) {
        uint128 baseTokenIn = uint128(baseToken.balanceOf(address(this))) - baseTokenReserves;
        uint128 fyTokenOut = baseTokenIn.rmul(rate);
        require(fyTokenOut >= min, "Pool: Not enough fyToken obtained");
        fyToken.transfer(to, fyTokenOut);
        (baseTokenReserves, fyTokenReserves) = (uint112(baseToken.balanceOf(address(this))), uint112(fyTokenReserves - fyTokenOut));
        return fyTokenOut;
    }

    function buyBaseToken(address to, uint128 baseTokenOut, uint128 max) external returns(uint128) {
        uint128 fyTokenIn = baseTokenOut.rmul(rate);
        require(fyTokenIn <= max, "Pool: Too much fyToken in");
        require(fyTokenReserves + fyTokenIn < getFYTokenReserves(), "Pool: Not enough fyToken in");
        baseToken.transfer(to, baseTokenOut);
        (baseTokenReserves, fyTokenReserves) = (uint112(baseTokenReserves - baseTokenOut), uint112(fyTokenReserves + fyTokenIn));
        return fyTokenIn;
    }

    function sellFYToken(address to, uint128 min) external returns(uint128) {
        uint128 fyTokenIn = uint128(fyToken.balanceOf(address(this))) - fyTokenReserves;
        uint128 baseTokenOut = fyTokenIn.rdiv(rate);
        require(baseTokenOut >= min, "Pool: Not enough baseToken obtained");
        baseToken.transfer(to, baseTokenOut);
        (baseTokenReserves, fyTokenReserves) = (uint112(baseTokenReserves - baseTokenOut), uint112(fyToken.balanceOf(address(this))));
        return baseTokenOut;
    }

    function buyFYToken(address to, uint128 fyTokenOut, uint128 max) external returns(uint128) {
        uint128 baseTokenIn = fyTokenOut.rdiv(rate);
        require(baseTokenIn <= max, "Pool: Too much base token in");
        require(baseTokenReserves + baseTokenIn < getBaseTokenReserves(), "Pool: Not enough base token in");
        fyToken.transfer(to, fyTokenOut);
        (baseTokenReserves, fyTokenReserves) = (uint112(baseTokenReserves + baseTokenIn), uint112(fyTokenReserves - fyTokenOut));
        return baseTokenIn;
    }
}
