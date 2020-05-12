pragma solidity ^0.6.2;

import "./../interfaces/IOracle.sol";


//Using fake contract instead of abstract for mocking
contract TestOracle is IOracle {
    uint256 internal _price; // collateral = dai * price, in RAY units

    function setPrice(uint256 price_) public {
        _price = price_;
    }

    function price() public override returns (uint256) {
        return _price;
    }
}
