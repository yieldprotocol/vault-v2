pragma solidity ^0.5.2;

import "./../IOracle.sol";

//Using fake contract instead of abstract for mocking
contract TestOracle is IOracle {
    uint256 price;

    function set(uint256 price_) public {
        price = price_;
    }

    function read() public view returns (uint256, bool) {
        return (price, price > 0);
    }
}
