pragma solidity ^0.5.2;

import "./IOracle.sol";

interface IOracle {
    /// @dev units of collateral per unit of underlying
    function get() external view returns (uint256);
}
