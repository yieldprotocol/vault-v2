// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I256.sol";
import {wadPow, wadDiv, wadMul} from "solmate/src/utils/SignedWadMath.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "../../interfaces/IOracle.sol";
import {ICrabStrategy} from "./CrabOracle.sol";
import {IUniswapV3PoolState} from "../uniswap/uniswapv0.8/pool/IUniswapV3PoolState.sol";

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
    using CastU256I256 for uint256;
    using CastBytes32Bytes6 for bytes32;
    using { wadDiv } for int256;
    using { wadPow } for int256;

    int256 public constant ONE = 1e18;
    int256 public constant BASE = 10001e14;

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
        uint256 zenBullUsdcPrice;
        (zenBullUsdcPrice, updateTime) = _getZenBullPrice();

        if (base == zenBullId && quote == usdcId) {
            quoteAmount = (zenBullUsdcPrice * baseAmount) / 1e18;
        } else if (base == usdcId && quote == zenBullId) {
            quoteAmount = (baseAmount * 1e18) / zenBullUsdcPrice;
        } else {
            revert ZenBullOracleUnsupportedAsset();
        }
        
    }

    /**
     * @notice Calculates the price of one zen bull token in USDC
     */
    function _getZenBullPrice() private view returns (uint256, uint256) {
        uint256 bullUSDCDebtBalance = eulerDToken.balanceOf(
            address(zenBullStrategy)
        );
        
        (uint256 crabEthBalance, uint256 craboSqthBalance) = zenBullStrategy
            .getCrabVaultDetails();

        (, int24 tick_, uint16 observationIndex, , , , ) = osqthWethPool.slot0();
        int256 tick = int256(tick_) * ONE; // Normalize tick
        int256 osqthWethPrice = ONE.wadDiv(BASE.wadPow(tick));
        
        (, tick_, observationIndex, , , , ) = wethUsdcPool.slot0();
        tick = int256(tick_) * ONE; // Normalize tick
        int256 wethUsdcPrice = ONE.wadDiv(BASE.wadPow(tick));

        int256 crabUsdcValue = wadMul(crabEthBalance.i256(), wethUsdcPrice) -
            wadMul(
                craboSqthBalance.i256(),
                wadMul(osqthWethPrice, wethUsdcPrice)
            );

        int256 crabUsdcPrice = wadDiv(crabUsdcValue, crabStrategy.totalSupply().i256());
        int256 bullUsdcValue = wadMul(zenBullStrategy.getCrabBalance().i256(), crabUsdcPrice) +
            wadMul(eulerEToken.balanceOf(
            address(zenBullStrategy)
        ).i256(), wethUsdcPrice) -
            bullUSDCDebtBalance.i256();

        uint256 bullUsdcPrice = uint256(
            wadDiv(bullUsdcValue, zenBullStrategy.totalSupply().i256())
        );

        (uint32 blockTimestamp, , , ) = wethUsdcPool.observations(observationIndex);
        
        return (bullUsdcPrice, blockTimestamp);
    }
}
