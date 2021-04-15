// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/vault-interfaces/IOracle.sol";


/// @dev An oracle that allows to set the spot price to anyone. It also allows to record spot values and return the accrual between a recorded and current spots.
contract OracleMock is IOracle {
    uint256 public spot;
    uint256 public updated;

    /// @dev Return the spot price
    function peek() external view virtual override returns (uint256, uint256) {
        return (spot, updated);
    }

    /// @dev Return the spot price
    function get() external virtual override returns (uint256, uint256) {
        updated = block.timestamp;
        return (spot, updated = block.timestamp);
    }

    /// @dev Set the spot price.
    function set(uint256 spot_) external {
        updated = block.timestamp;
        spot = spot_;
    }
}