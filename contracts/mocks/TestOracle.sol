pragma solidity ^0.6.2;

import "./../interfaces/IOracle.sol";


//Using fake contract instead of abstract for mocking
contract TestOracle is IOracle {
    uint256 internal price; // units of collateral per dai in RAY

    function setPrice(uint256 price_) public {
        price = price_;
    }

    function price() public view override returns (uint256) {
        return price;
    }
}
