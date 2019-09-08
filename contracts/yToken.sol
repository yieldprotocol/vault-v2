pragma solidity ^0.5.0;

import 'openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol';
import 'openzeppelin-solidity/contracts/token/ERC20/ERC20Burnable.sol';


contract yToken is ERC20Burnable, ERC20Mintable {
  uint256 era;

  constructor(uint256 era_) public {
      era = era_;
  }


}
