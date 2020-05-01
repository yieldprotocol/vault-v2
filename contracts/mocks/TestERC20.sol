pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract TestERC20 is ERC20("Test", "TST") {
    constructor (uint256 supply) public {
        _mint(msg.sender, supply);
    }


    function mint(uint256 amount) public {
        _mint(msg.sender, amount);
    }
}