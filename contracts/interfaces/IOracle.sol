pragma solidity ^0.6.2;


interface IOracle {
    /// @dev units of collateral per unit of dai, in RAY
    function price() external view returns (uint256);
}
