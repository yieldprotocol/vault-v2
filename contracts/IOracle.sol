pragma solidity ^0.5.2;

import "./IOracle.sol";

interface IOracle {
    function read() external view returns (uint256, bool);
}
