// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@yield-protocol/utils-v2/contracts/access/Ownable.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "../../math/CastBytes32Bytes6.sol";
import "./AggregatorV3Interface.sol";


/**
 * @title ChainlinkMultiOracle
 */
contract ChainlinkMultiOracle is IOracle, Ownable {
    using CastBytes32Bytes6 for bytes32;

    event SourcesSet(bytes6[] indexed bases, bytes6[] indexed quotes, address[] indexed sources_);

    uint public constant SCALE_FACTOR = 1e10; // Since Chainlink has 8 dec places, and peek() needs 18

    mapping(bytes6 => mapping(bytes6 => address)) public sources;

    /**
     * @notice Set or reset a number of oracle sources
     */
    function setSources(bytes6[] memory bases, bytes6[] memory quotes, address[] memory sources_) public onlyOwner {
        require(bases.length == quotes.length && quotes.length == sources_.length, "Mismatched inputs");
        for (uint256 i = 0; i < bases.length; i++)
            sources[bases[i]][quotes[i]] = sources_[i];
        emit SourcesSet(bases, quotes, sources_);
    }

    /**
     * @notice Retrieve the latest price of the price oracle.
     * @return price
     */
    function _peek(bytes6 base, bytes6 quote) private view returns (uint price, uint updateTime) {
        int rawPrice;
        (, rawPrice,, updateTime,) = AggregatorV3Interface(sources[base][quote]).latestRoundData();
        require(rawPrice > 0, "Chainlink price <= 0");
        price = uint(rawPrice) * SCALE_FACTOR;
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * @return value
     */
    function peek(bytes32 base, bytes32 quote, uint256 amount) public virtual override view returns (uint256 value, uint256 updateTime) {
        uint256 price;
        (price, updateTime) = _peek(bytes6(base), bytes6(quote));
        value = price * amount / 1e18;
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.. Same as `peek` for this oracle.
     * @return value
     */
    function get(bytes32 base, bytes32 quote, uint256 amount) public virtual override view returns (uint256 value, uint256 updateTime) {
        uint256 price;
        (price, updateTime) = _peek(bytes6(base), bytes6(quote));
        value = price * amount / 1e18;
    }
}
