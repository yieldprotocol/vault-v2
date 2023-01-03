// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "../../interfaces/IOracle.sol";
import {ICrabStrategy} from "./CrabOracle.sol";
import {IUniswapV3PoolState} from "../uniswap/uniswapv0.8/pool/IUniswapV3PoolState.sol";

interface IZenBullStrategy {
    /**
     * @notice return the internal accounting of the bull strategy's crab balance
     * @return crab token amount hold by the bull strategy
     */
    function getCrabBalance() external view returns (uint256);

    /**
     * @notice get crab vault debt and collateral details
     * @return vault eth collateral, vault wPowerPerp debt
     */
    function getCrabVaultDetails() external view returns (uint256, uint256);

    function totalSupply() external view returns (uint256);
}

/// @notice Returns price of zen bull token in USDC & vice versa
contract ZenBullOracle is IOracle {
    using CastBytes32Bytes6 for bytes32;

    ICrabStrategy immutable crabStrategy;
    IZenBullStrategy immutable zenBullStrategy;
    IUniswapV3PoolState immutable osqthWethPool;
    IUniswapV3PoolState immutable wethUsdcPool;
    IERC20 immutable eulerDToken;
    IERC20 immutable eulerEToken;

    constructor(
        ICrabStrategy crabStrategy_,
        IZenBullStrategy zenBullStrategy_,
        IUniswapV3PoolState osqthWethPool_,
        IUniswapV3PoolState wethUsdcPool_,
        IERC20 eulerDToken_,
        IERC20 eulerEToken_
    ) {
        crabStrategy = crabStrategy_;
        zenBullStrategy = zenBullStrategy_;
        osqthWethPool = osqthWethPool_;
        wethUsdcPool = wethUsdcPool_;
        eulerDToken = eulerDToken_;
        eulerEToken = eulerEToken_;
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * Only `zenBullId` and `usdcId` are accepted as asset identifiers.
     */
    function peek(
        bytes32 base,
        bytes32 quote,
        uint256 baseAmount
    )
        external
        view
        virtual
        override
        returns (uint256 quoteAmount, uint256 updateTime)
    {
        return _peek(base.b6(), quote.b6(), baseAmount);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price. Same as `peek` for this oracle.
     * Only `zenBullId` and `usdcId` are accepted as asset identifiers.
     */
    function get(
        bytes32 base,
        bytes32 quote,
        uint256 baseAmount
    )
        external
        virtual
        override
        returns (uint256 quoteAmount, uint256 updateTime)
    {
        return _peek(base.b6(), quote.b6(), baseAmount);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function _peek(
        bytes6 base,
        bytes6 quote,
        uint256 baseAmount
    ) private view returns (uint256 quoteAmount, uint256 updateTime) {}

    function _getZenBullPrice() private view returns (uint256) {
        uint256 bullUSDCDebtBalance = eulerDToken.balanceOf(
            address(zenBullStrategy)
        );
        uint256 bullWethCollateralBalance = eulerEToken.balanceOf(
            address(zenBullStrategy)
        );
        uint256 bullCrabBalance = zenBullStrategy.getCrabBalance();
        (uint256 crabEthBalance, uint256 craboSqthBalance) = zenBullStrategy
            .getCrabVaultDetails();
        uint256 crabTotalSupply = crabStrategy.totalSupply();
        uint256 bullTotalSupply = zenBullStrategy.totalSupply();

        (, int24 tick, , , , , ) = osqthWethPool.slot0();
        uint256 osqthWethPrice = (10000 / (10001**uint256(int256(tick))));
        (, tick, , , , , ) = wethUsdcPool.slot0();
        uint256 wethUsdcPrice = (10000 /
            (10001**uint256(int256(tick)) * 10**(6 - 18)));
        uint256 crabUsdcValue = ((crabEthBalance / 1e18) *
            wethUsdcPrice -
            (craboSqthBalance / 1e18) *
            osqthWethPrice *
            wethUsdcPrice);

        uint256 crabUsdcPrice = crabUsdcValue / (crabTotalSupply / 1e18);
        uint256 bullUsdcValue = (bullCrabBalance / 1e18) *
            crabUsdcPrice +
            (bullWethCollateralBalance / 1e18) *
            wethUsdcPrice -
            bullUSDCDebtBalance /
            1e6;
        uint256 bullUsdcPrice = bullUsdcValue / (bullTotalSupply / 1e18);
        return bullUsdcPrice;
    }
}
