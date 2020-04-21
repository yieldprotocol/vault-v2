pragma solidity ^0.5.2;

import "./../IOracle.sol";


//Using fake contract instead of abstract for mocking
contract TestOracle is IOracle {
    uint256 internal price;

    function set(uint256 price_) public {
        price = price_;
    }

    function get() public view returns (uint256) {
        return price;
    }
}
