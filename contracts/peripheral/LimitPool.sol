// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../pool/Pool.sol";
import "../interfaces/IPool.sol";



/// @dev LimitPool is a proxy contract to Pool that implements limit orders.
contract LimitPool {

    /// @dev Sell Dai for yDai
    /// @param to Wallet receiving the yDai being bought
    /// @param daiIn Amount of dai being sold
    /// @param minYDaiOut Minimum amount of yDai being bought
    function sellDai(address pool, address to, uint128 daiIn, uint128 minYDaiOut)
        external
        returns(uint256)
    {
        uint256 yDaiOut = IPool(pool).sellDai(msg.sender, to, daiIn);
        require(
            yDaiOut >= minYDaiOut,
            "LimitPool: Limit not reached"
        );
        return yDaiOut;
    }

    /// @dev Buy Dai for yDai
    /// @param to Wallet receiving the dai being bought
    /// @param daiOut Amount of dai being bought
    /// @param maxYDaiIn Maximum amount of yDai being sold
    function buyDai(address pool, address to, uint128 daiOut, uint128 maxYDaiIn)
        external
        returns(uint256)
    {
        uint256 yDaiIn = IPool(pool).buyDai(msg.sender, to, daiOut);
        require(
            maxYDaiIn >= yDaiIn,
            "LimitPool: Limit exceeded"
        );
        return yDaiIn;
    }

    /// @dev Sell yDai for Dai
    /// @param to Wallet receiving the dai being bought
    /// @param yDaiIn Amount of yDai being sold
    /// @param minDaiOut Minimum amount of dai being bought
    function sellYDai(address pool, address to, uint128 yDaiIn, uint128 minDaiOut)
        external
        returns(uint256)
    {
        uint256 daiOut = IPool(pool).sellYDai(msg.sender, to, yDaiIn);
        require(
            daiOut >= minDaiOut,
            "LimitPool: Limit not reached"
        );
        return daiOut;
    }

    /// @dev Buy yDai for dai
    /// @param to Wallet receiving the yDai being bought
    /// @param yDaiOut Amount of yDai being bought
    /// @param maxDaiIn Maximum amount of dai being sold
    function buyYDai(address pool, address to, uint128 yDaiOut, uint128 maxDaiIn)
        external
        returns(uint256)
    {
        uint256 daiIn = IPool(pool).buyYDai(msg.sender, to, yDaiOut);
        require(
            maxDaiIn >= daiIn,
            "LimitPool: Limit exceeded"
        );
        return daiIn;
    }
}