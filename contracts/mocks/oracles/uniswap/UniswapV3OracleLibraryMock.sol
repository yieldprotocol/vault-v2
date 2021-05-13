// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "../../../math/WMul.sol";
import "./UniswapV3FactoryMock.sol";
import "./UniswapV3PoolMock.sol";

/// @title Uniswap V3 Oracle Library Mock
/// @notice Just for testing purposes
library UniswapV3OracleLibraryMock {

    using WMul for uint256;

    /// @notice Always provides the double of the base amount as the price of the base token expressed in the quote token
    function consult(
        address factory,
        address baseToken,
        address quoteToken,
        uint24 fee,
        uint256 baseAmount,
        uint32 /* secondsAgo */
    ) internal view returns (uint256 quoteAmount) {
        address pool = UniswapV3FactoryMock(factory).getPool(baseToken, quoteToken, fee);
        return baseAmount.wmul(UniswapV3PoolMock(pool).price());
    }
}