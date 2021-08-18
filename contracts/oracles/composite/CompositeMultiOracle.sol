// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.1;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";


/**
 * @title CompositeMultiOracle
 */
contract CompositeMultiOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;

    uint8 public constant override decimals = 18;   // All prices are converted to 18 decimals

    event SourceSet(bytes6 indexed baseId, bytes6 indexed quoteId, IOracle indexed source);
    event PathSet(bytes6 indexed baseId, bytes6 indexed quoteId, bytes6[] indexed path);

    mapping(bytes6 => mapping(bytes6 => IOracle)) public sources;
    mapping(bytes6 => mapping(bytes6 => bytes6[])) public paths;

    /**
     * @notice Set or reset an oracle source
     */
    function setSource(bytes6 base, bytes6 quote, IOracle source) external auth {
        _setSource(base, quote, source);
    }

    /**
     * @notice Set or reset a number of oracle sources
     */
    function setSources(bytes6[] memory bases, bytes6[] memory quotes, IOracle[] memory sources_) external auth {
        uint256 length = bases.length;
        require(
            length == quotes.length && 
            length == sources_.length,
            "Mismatched inputs"
        );
        for (uint256 i; i < length; i++) {
            _setSource(bases[i], quotes[i], sources_[i]);
        }
    }

    /**
     * @notice Set or reset an price path
     */
    function setPath(bytes6 base, bytes6 quote, bytes6[] memory path) external auth {
        _setPath(base, quote, path);
    }

    /**
     * @notice Set or reset a number of price paths
     */
    function setPaths(bytes6[] memory bases, bytes6[] memory quotes, bytes6[][] memory paths_) external auth {
        uint256 length = bases.length;
        require(
            length == quotes.length && 
            length == paths_.length,
            "Mismatched inputs"
        );
        for (uint256 i; i < length; i++) {
            _setPath(bases[i], quotes[i], paths_[i]);
        }
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function peek(bytes32 base, bytes32 quote, uint256 amount)
        external view virtual override
        returns (uint256 value, uint256 updateTime)
    {
        value = amount;
        updateTime = block.timestamp;
        bytes6 base_ = base.b6();
        bytes6 quote_ = quote.b6();
        bytes6[] memory path = paths[base_][quote_];
        for (uint256 p = 0; p < path.length; p++) {
            (value, updateTime) = _peek(base_, path[p], value, updateTime);
            base_ = path[p];
        }
        (value, updateTime) = _peek(base_, quote_, value, updateTime);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price, updating it if possible.
     */
    function get(bytes32 base, bytes32 quote, uint256 amount)
        external virtual override
        returns (uint256 value, uint256 updateTime)
    {
        value = amount;
        updateTime = block.timestamp;
        bytes6 base_ = base.b6();
        bytes6 quote_ = quote.b6();
        bytes6[] memory path = paths[base_][quote_];
        for (uint256 p = 0; p < path.length; p++) {
            (value, updateTime) = _get(base_, path[p], value, updateTime);
            base_ = path[p];
        }
        (value, updateTime) = _get(base_, quote_, value, updateTime);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     */
    function _peek(bytes6 base, bytes6 quote, uint256 amount, uint256 updateTimeIn)
        private view returns (uint256 value, uint256 updateTimeOut)
    {
        IOracle source = sources[base][quote];
        require (source != IOracle(address(0)), "Source not found");
        (value, updateTimeOut) = source.peek(base, quote, amount);
        updateTimeOut = (updateTimeOut < updateTimeIn) ? updateTimeOut : updateTimeIn; // Take the oldest update time
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price, updating it if possible.
     */
    function _get(bytes6 base, bytes6 quote, uint256 amount, uint256 updateTimeIn)
        private returns (uint256 value, uint256 updateTimeOut)
    {
        IOracle source = sources[base][quote];
        require (source != IOracle(address(0)), "Source not found");
        (value, updateTimeOut) = source.get(base, quote, amount);
        updateTimeOut = (updateTimeOut < updateTimeIn) ? updateTimeOut : updateTimeIn; // Take the oldest update time
    }

    /**
     * @dev Set a new price source. It must conform to the IOracle interface and have the same decimals.
     */
    function _setSource(bytes6 base, bytes6 quote, IOracle source) internal {
        require (source.decimals() == decimals, "Unsupported decimals");
        sources[base][quote] = source;
        emit SourceSet(base, quote, source);
    }

    /**
     * @dev Set a new price source as the combination of multiple already registered sources.
     */
    function _setPath(bytes6 base, bytes6 quote, bytes6[] memory path) internal {
        bytes6 base_ = base;
        for (uint256 p = 0; p < path.length; p++) {
            require (sources[base_][path[p]] != IOracle(address(0)), "Source not found");
            base_ = path[p];
        }
        paths[base][quote] = path;
        emit PathSet(base, quote, path);
    }
}
