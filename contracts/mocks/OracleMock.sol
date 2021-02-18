// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "../interfaces/IOracle.sol";

contract OracleMock is IOracle {
    /// @dev Return the spot price.
    function spot() external view returns (uint256) {
        return(1e27);
    }

    /// @dev Record the current spot price at the `maturity` timestamp, if we haven't done it yet and are at or past maturity.
    function record(uint32 maturity) external {
        //todo: implement
    }

    /// @dev Return the increase in spot price between now and the recorded price at `maturity`.
    function accrual(uint32 maturity) external view returns (uint256){
        //todo: implement
    }

}