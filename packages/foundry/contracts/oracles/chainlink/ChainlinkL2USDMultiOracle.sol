// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import './ChainlinkUSDMultiOracle.sol';


/**
 * @title ChainlinkL2USDMultiOracle: ChainlinkUSDMultiOracle that's safe to use on L2
 * @notice Chainlink recommends checking the sequencer status on some L2 networks to avoid
  reading stale data

  https://docs.chain.link/docs/l2-sequencer-flag/
 */
contract ChainlinkL2USDMultiOracle is ChainlinkUSDMultiOracle {
    using CastBytes32Bytes6 for bytes32;

    FlagsInterface public chainlinkFlags;
    // https://docs.chain.link/docs/l2-sequencer-flag/
    address internal constant FLAG_ARBITRUM_SEQ_OFFLINE =
        address(bytes20(bytes32(uint256(keccak256('chainlink.flags.arbitrum-seq-offline')) - 1)));

    constructor(FlagsInterface flags) {
        require(address(flags) != address(0), 'FlagsInterface has to be set');
        chainlinkFlags = flags;
    }

    modifier onlyFresh() {
        // If flag is raised we shouldn't perform any critical operations
        require(!chainlinkFlags.getFlag(FLAG_ARBITRUM_SEQ_OFFLINE), 'Chainlink feeds are not being updated');
        _;
    }

    /// @dev Convert amountBase base into quote at the latest oracle price.
    function peek(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    ) external view virtual override onlyFresh returns (uint256 amountQuote, uint256 updateTime) {
        if (baseId == quoteId) return (amountBase, block.timestamp);

        (amountQuote, updateTime) = _peekThroughUSD(baseId.b6(), quoteId.b6(), amountBase);
    }

    /// @dev Convert amountBase base into quote at the latest oracle price, updating state if necessary. Same as `peek` for this oracle.
    function get(
        bytes32 baseId,
        bytes32 quoteId,
        uint256 amountBase
    ) external virtual override onlyFresh returns (uint256 amountQuote, uint256 updateTime) {
        if (baseId == quoteId) return (amountBase, block.timestamp);

        (amountQuote, updateTime) = _peekThroughUSD(baseId.b6(), quoteId.b6(), amountBase);
    }
}
