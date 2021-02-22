// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "../interfaces/IOracle.sol";


library RMath { // Fixed point arithmetic in Ray units
    /// @dev Divide an unsigned integer by another, returning a fixed point factor in ray units
    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * 1e27 / y; // We just rely on built-in exceptions
    }
}

/// @dev An oracle that allows to set the spot price to anyone. It also allows to record spot values and return the accrual between a recorded and current spots.
contract OracleMock is IOracle {
    using RMath for uint256;

    event SpotRecorded(uint32 maturity, uint256 spot);

    uint256 internal _spot;
    mapping(uint32 => uint256) public recorded;

    /// @dev Return the spot price
    function spot() external view override returns (uint256) {
        return _spot;
    }

    /// @dev Record the current spot price at the `maturity` timestamp, if we haven't done it yet and are at or past maturity.
    function record(uint32 maturity) external override {
        uint32 _now = uint32(block.timestamp);
        require(_now >= maturity, "Record after maturity");
        require(recorded[maturity] == 0, "Already recorded a value");
        recorded[maturity] = _spot;
        emit SpotRecorded(maturity, _spot);
    }

    /// @dev Return the increase in spot price between now and the recorded price at `maturity`.
    function accrual(uint32 maturity) external view override returns (uint256){
        uint256 _recorded = recorded[maturity];
        require (_recorded > 0, "No recorded spot");
        return _spot.rdiv(_recorded);
    }

    /// @dev Set the spot price.
    function setSpot(uint256 spot_) external {
        _spot = spot_;
    }
}