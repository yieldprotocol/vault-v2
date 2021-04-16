// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/vault-interfaces/IOracle.sol";


/// @dev An oracle that allows to set the spot price to anyone. It also allows to record spot values and return the accrual between a recorded and current spots.
contract OracleMock is IOracle {

    address public immutable override source;

    uint256 public spot;
    uint256 public updated;

    constructor() {
        source = address(this);
    }

    /// @dev Return the spot price with 18 decimals.
    function peek() external view virtual override returns (uint256, uint256) {
        return (spot, updated);
    }

    /// @dev Return the spot price with 18 decimals.
    function get() external virtual override returns (uint256, uint256) {
        updated = block.timestamp;
        return (spot, updated = block.timestamp);
    }

    /// @dev Set the spot price with 18 decimals. Overriding contracts with different formats must convert from 18 decimals.
    function set(uint256 spot_) external virtual {
        updated = block.timestamp;
        spot = spot_;
    }
}