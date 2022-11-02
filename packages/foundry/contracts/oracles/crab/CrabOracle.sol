// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import "../../interfaces/IOracle.sol";

interface ICrabStrategy {
    function totalSupply() external view returns (uint256);

    /**
     * @notice get the vault composition of the strategy
     * @return operator
     * @return nft collateral id
     * @return collateral amount
     * @return short amount
     */
    function getVaultDetails()
        external
        view
        returns (
            address,
            uint256,
            uint256,
            uint256
        );
}

/**
 * @title CrabOracle
 * @notice Oracle to fetch Crab-ETH exchange amounts
 */
contract CrabOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;
    ICrabStrategy crabStrategy;
    IOracle uniswapV3Oracle =
        IOracle(0x358538ea4F52Ac15C551f88C701696f6d9b38F3C);
    // TODO: Update this before deployment
    bytes6 public constant crab = 0x323900000000;
    bytes6 public constant weth = 0x303100000000;
    bytes6 public constant oSQTH = 0x313900000000;

    constructor(ICrabStrategy crabStrategy_) {
        crabStrategy = crabStrategy_;
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * Only `wstEthId` and `stEthId` are accepted as asset identifiers.
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
     * Only `wstEthId` and `stEthId` are accepted as asset identifiers.
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
        require(
            (base == crab && quote == weth) || (base == weth && quote == crab),
            "Source not found"
        );
        (, , uint256 ethCollateral, uint256 oSQTHDebt) = crabStrategy
            .getVaultDetails();

        // Crab Price calculation
        (uint256 oSQTHPrice, uint256 updatTime) = uniswapV3Oracle.peek(
            oSQTH,
            weth,
            1e18
        );
        require(updatTime != 0, "Incomplete round");
        uint256 crabPrice = (ethCollateral * 1e18 - oSQTHPrice * oSQTHDebt) /
            crabStrategy.totalSupply();

        if (base == crab) {
            //Base equals crab
            quoteAmount = (crabPrice * baseAmount) / 1e18;
        } else if (quote == crab) {
            //Base equals weth
            quoteAmount = (baseAmount * 1e18) / crabPrice;
        }

        updateTime = block.timestamp;
    }
}
