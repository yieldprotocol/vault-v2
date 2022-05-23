// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "./IV1FYDai.sol";
import "./IV1Pool.sol";
import "../LadleStorage.sol";


contract BurnV1LiquidityModule {

    IV1Pool public immutable sepPool;
    IV1Pool public immutable decPool;

    constructor (IV1Pool sepPool_, IV1Pool decPool_) 
    {
        sepPool = sepPool_;
        decPool = decPool_;
    }

    /// @dev Burns mature v1 LP tokens by redeeming fyDai for Dai
    /// @param pool Pool to burn LP tokens from.
    /// @param poolTokens amount of pool tokens to burn. 
    function burnForDai(IV1Pool pool, address to, uint256 poolTokens) public {
        require(pool == sepPool || pool == decPool, "Unknown pool");

        IV1FYDai fyDai = pool.fyDai();

        (uint256 daiObtained, uint256 fyDaiObtained) = pool.burn(address(this), address(this), poolTokens);
        uint256 daiFromFYDai;

        daiFromFYDai = fyDai.redeem(address(this), address(this), fyDaiObtained);

        require(pool.dai().transfer(to, daiObtained + daiFromFYDai), "Dai Transfer Failed");
    }
}