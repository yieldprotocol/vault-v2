// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import {wadPow, wadDiv, wadMul} from "solmate/utils/SignedWadMath.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "../../interfaces/IOracle.sol";
import {ICrabStrategy} from "./CrabOracle.sol";
import {IUniswapV3PoolState} from "../uniswap/uniswapv0.8/pool/IUniswapV3PoolState.sol";
import "forge-std/src/console.sol";

error ZenBullOracleUnsupportedAsset();

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
/// @dev Based on calculations provided by Opyn team https://gist.github.com/iamsahu/91428eb2029f4a78eabbe26ed7490087
contract ZenBullOracle is IOracle {
    using CastBytes32Bytes6 for bytes32;

    ICrabStrategy public immutable crabStrategy;
    IZenBullStrategy public immutable zenBullStrategy;
    IUniswapV3PoolState public immutable osqthWethPool;
    IUniswapV3PoolState public immutable wethUsdcPool;
    IERC20 public immutable eulerDToken;
    IERC20 public immutable eulerEToken;
    bytes6 public immutable usdcId;
    bytes6 public immutable zenBullId;

    event SourceSet(
        ICrabStrategy crabStrategy,
        IZenBullStrategy zenBullStrategy,
        IUniswapV3PoolState osqthWethPool,
        IUniswapV3PoolState wethUsdcPool,
        IERC20 eulerDToken,
        IERC20 eulerEToken
    );

    constructor(
        ICrabStrategy crabStrategy_,
        IZenBullStrategy zenBullStrategy_,
        IUniswapV3PoolState osqthWethPool_,
        IUniswapV3PoolState wethUsdcPool_,
        IERC20 eulerDToken_,
        IERC20 eulerEToken_,
        bytes6 usdcId_,
        bytes6 zenBullId_
    ) {
        crabStrategy = crabStrategy_;
        zenBullStrategy = zenBullStrategy_;
        osqthWethPool = osqthWethPool_;
        wethUsdcPool = wethUsdcPool_;
        eulerDToken = eulerDToken_;
        eulerEToken = eulerEToken_;
        usdcId = usdcId_;
        zenBullId = zenBullId_;
        emit SourceSet(
            crabStrategy_,
            zenBullStrategy_,
            osqthWethPool_,
            wethUsdcPool_,
            eulerDToken_,
            eulerEToken_
        );
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
    ) private view returns (uint256 quoteAmount, uint256 updateTime) {
        if (base == zenBullId && quote == usdcId) {
            quoteAmount = (_getZenBullPrice() * baseAmount) / 1e18;
        } else if (base == usdcId && quote == zenBullId) {
            quoteAmount = (baseAmount * 1e18) / _getZenBullPrice();
        } else {
            revert ZenBullOracleUnsupportedAsset();
        }
        updateTime = block.timestamp;
    }

    /**
     * @notice Calculates the price of one zen bull token in USDC
     */
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
        int256 osqthWethPrice = wadDiv(
            1e18,
            wadPow(10001e14, int256(tick) * 1e18)
        );
        (, tick, , , , , ) = wethUsdcPool.slot0();
        int256 wethUsdcPrice = wadDiv(
            1e18,
            wadPow(10001e14, int256(tick) * 1e18)
        );

        int256 crabUsdcValue = wadMul(int256(crabEthBalance), wethUsdcPrice) -
            wadMul(
                int256(craboSqthBalance),
                wadMul(osqthWethPrice, wethUsdcPrice)
            );

        int256 crabUsdcPrice = wadDiv(crabUsdcValue, int256(crabTotalSupply));
        int256 bullUsdcValue = wadMul(int256(bullCrabBalance), crabUsdcPrice) +
            wadMul(int256(bullWethCollateralBalance), wethUsdcPrice) -
            int256(bullUSDCDebtBalance);

        uint256 bullUsdcPrice = uint256(
            wadDiv(bullUsdcValue, int256(bullTotalSupply))
        );
        return bullUsdcPrice;
    }
}
