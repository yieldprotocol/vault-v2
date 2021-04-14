// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/vault-interfaces/IOracle.sol";


/// @dev An oracle that allows to set the spot price to anyone. It also allows to record spot values and return the accrual between a recorded and current spots.
contract OracleMock is IOracle {
    uint128 internal _spot;
    mapping(uint32 => uint128) public recorded;

    /// @dev Return the spot price
    function spot() external view override returns (uint128) {
        return _spot;
    }

    /// @dev Set the spot price.
    function setSpot(uint128 spot_) external {
        _spot = spot_;
    }
}