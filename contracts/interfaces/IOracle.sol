pragma solidity ^0.6.2;

import "./IOracle.sol";

interface IOracle {
    /// @dev units of collateral per unit of underlying, in ray
    function get() external view returns (uint256);
}
