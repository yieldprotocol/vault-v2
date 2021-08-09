// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.1;

import "@yield-protocol/vault-interfaces/IOracle.sol";
// import "@yield-protocol/yieldspace-interfaces/IPool.sol";

interface IPool {
    function getCache() external view returns (uint112, uint112, uint32);
}

library CastU256U112 {
    /// @dev Safely cast an uint256 to an uint112
    function u112(uint256 x) internal pure returns (uint112 y) {
        require (x <= type(uint112).max, "Cast overflow");
        y = uint112(x);
    }
}

/**
 * @title YieldSpaceOracle
 */
contract YieldSpaceOracle is IOracle {
    using CastU256U112 for uint256;
    uint8 public constant override decimals = 18;   // All prices are converted to 18 decimals
    uint public constant PERIOD = 1 hours;

    address public immutable source;

    uint112 public ratioBaseAverage;
    uint32  public blockTimestampLast;
    uint112 public ratioBaseCumulativeLast;

    constructor(IPool pool_) {
        source = address(pool_);
    }

    function update() external {
        _update();
    }

    /// @dev Update the cumulative ratioSeconds if PERIOD has passed.
    function _update() internal {
        (uint256 baseReserves, uint256 fyTokenReserves, uint32 blockTimestamp) = IPool(source).getCache();
        (uint32 blockTimestampLast_, uint112 ratioBaseCumulativeLast_) = (blockTimestampLast, ratioBaseCumulativeLast);

        require(baseReserves > 0 && fyTokenReserves > 0, "No liquidity in the pool");
        uint112 ratioBaseCumulative = ((1e18 * baseReserves * blockTimestamp) / fyTokenReserves).u112();
        uint32 timeElapsed = blockTimestamp - blockTimestampLast_;

        // ensure that at least one full period has passed since the last update
        if(timeElapsed >= PERIOD) {
            // cumulative price is in (ratio * seconds) units so we simply wrap it after division by time elapsed
            (ratioBaseAverage, blockTimestampLast, ratioBaseCumulativeLast) = (
                uint112((ratioBaseCumulative - ratioBaseCumulativeLast_) / timeElapsed),  // average, casting won't overflow
                blockTimestamp,
                ratioBaseCumulative                                                     // last
            );
        }
    }

    /// @dev Return the cumulative ratioSeconds
    function peek(bytes32, bytes32, uint256)
        external view virtual override
        returns (uint256 ratio, uint256 updateTime)
    {
        (ratio, updateTime) = (ratioBaseAverage, blockTimestampLast);
        require(updateTime != 0, "Not initialized");
    }

    /// @dev Update and return the cumulative ratioSeconds
    function get(bytes32, bytes32, uint256)
        external virtual override
        returns (uint256 ratio, uint256 updateTime)
    {
        _update();
        ratio = ratioBaseAverage;
        updateTime = blockTimestampLast;
    }
}
