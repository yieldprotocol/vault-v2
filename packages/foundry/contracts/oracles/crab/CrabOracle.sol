// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
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
contract CrabOracle is IOracle {
    using Cast for bytes32;
    ICrabStrategy immutable crabStrategy;
    IOracle immutable uniswapV3Oracle;
    bytes6 immutable ethId;
    bytes6 immutable crabId;
    bytes6 immutable oSQTHId;

    event SourceSet(
        bytes6 crab_,
        bytes6 oSQTH_,
        bytes6 ethId_,
        ICrabStrategy indexed crabStrategy_,
        IOracle indexed uniswapV3Oracle_
    );

    /**
     * @notice Set crabstrategy & uniswap source
     */
    constructor(
        bytes6 crabId_,
        bytes6 oSQTHId_,
        bytes6 ethId_,
        ICrabStrategy crabStrategy_,
        IOracle uniswapV3Oracle_
    ) {
        crabId = crabId_;
        oSQTHId = oSQTHId_;
        ethId = ethId_;
        crabStrategy = crabStrategy_;
        uniswapV3Oracle = uniswapV3Oracle_;

        emit SourceSet(
            crabId_,
            oSQTHId_,
            ethId_,
            crabStrategy_,
            uniswapV3Oracle_
        );
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * Only `crabId` and `ethId` are accepted as asset identifiers.
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
     * Only `crabId` and `ethId` are accepted as asset identifiers.
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
            (base == crabId && quote == ethId) ||
                (base == ethId && quote == crabId),
            "Source not found"
        );

        if (base == crabId) {
            quoteAmount = (_getCrabPrice() * baseAmount) / 1e18; // 1e18 is used to Normalize
        } else if (quote == crabId) {
            quoteAmount = (baseAmount * 1e18) / _getCrabPrice(); // 1e18 is used to Normalize
        }

        updateTime = block.timestamp;
    }

    /// @notice Returns price of one crab token in terms of ETH
    /// @return crabPrice Price of one crab token in terms of ETH
    function _getCrabPrice() internal view returns (uint256 crabPrice) {
        // Get ETH collateral & oSQTH debt of the crab strategy
        (, , uint256 ethCollateral, uint256 oSQTHDebt) = crabStrategy
            .getVaultDetails();
        // Get oSQTH price from uniswapOracle
        (uint256 oSQTHPrice, uint256 lastUpdateTime) = uniswapV3Oracle.peek(
            oSQTHId,
            ethId,
            1e18
        );
        require(lastUpdateTime != 0, "Incomplete round");
        // Crab Price calculation
        // Crab at any point has a combination of ETH collateral and squeeth debt so you can calc crab/eth value with:
        // Crab net value in eth terms = Eth collateral - oSQTH/ETH price * (oSQTH debt)
        // Price of 1 crab in terms of ETH = Crab net value / totalSupply of Crab
        crabPrice =
            (ethCollateral * 1e18 - oSQTHPrice * oSQTHDebt) /
            crabStrategy.totalSupply();
    }
}
