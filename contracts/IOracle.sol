pragma solidity ^0.5.2;

import "./IOracle.sol";

interface IOracle {
    function get() external view returns (uint256);
}
