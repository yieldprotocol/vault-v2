pragma solidity ^0.5.2;

//Using fake contract instead of abstract for mocking
contract Oracle {
    uint256 price;

    function set(uint256 price_) public {
        price = price_;
    }

    function read() external view returns (uint256) {
        require(price > 0, "Inpriceid price feed");
        return price;
    }

    function peek() external view returns (uint256,bool) {
        return (price, price > 0);
    }

}
