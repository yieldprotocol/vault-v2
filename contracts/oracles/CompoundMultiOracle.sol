// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@yield-protocol/utils-v2/contracts/access/Ownable.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "../math/CastBytes32Bytes6.sol";
import "./CTokenInterface.sol";


contract CompoundMultiOracle is IOracle, Ownable {
    using CastBytes32Bytes6 for bytes32;

    event SourcesSet(bytes6[] indexed bases, bytes32[] indexed kinds, address[] indexed sources_);

    uint public constant SCALE_FACTOR = 1; // I think we don't need scaling for rate and chi oracles

    mapping(bytes6 => mapping(bytes32 => address)) public sources;

    /**
     * @notice Set or reset a number of oracle sources
     */
    function setSources(bytes6[] memory bases, bytes32[] memory kinds, address[] memory sources_) public onlyOwner {
        require(bases.length == kinds.length && kinds.length == sources_.length, "Mismatched inputs");
        for (uint256 i = 0; i < bases.length; i++)
            sources[bases[i]][kinds[i]] = sources_[i];
        emit SourcesSet(bases, kinds, sources_);
    }

    /**
     * @notice Retrieve the latest price of a given source.
     * @return price
     */
    function _peek(bytes6 base, bytes32 kind) private view returns (uint price, uint updateTime) {
        uint256 rawPrice;
        
        if (kind == "rate") rawPrice = CTokenInterface(sources[base][kind]).borrowIndex();
        else if (kind == "chi") rawPrice = CTokenInterface(sources[base][kind]).exchangeRateStored();
        else revert("Unknown oracle type");

        require(rawPrice > 0, "Compound price is zero");

        price = rawPrice * SCALE_FACTOR;
        updateTime = block.timestamp;
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * @return value
     */
    function peek(bytes32 base, bytes32 kind, uint256 amount) public virtual override view returns (uint256 value, uint256 updateTime) {
        uint256 price;
        (price, updateTime) = _peek(base.b6(), kind);
        value = price * amount / 1e18;
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price. Same as `peek` for this oracle.
     * @return value
     */
    function get(bytes32 base, bytes32 kind, uint256 amount) public virtual override view returns (uint256 value, uint256 updateTime) {
        uint256 price;
        (price, updateTime) = _peek(base.b6(), kind);
        value = price * amount / 1e18;
    }
}