pragma solidity ^0.5.2;

import '@openzeppelin/contracts/token/ERC20/ERC20Mintable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol';


contract yToken is ERC20Burnable, ERC20Mintable {
  uint256 public when;

  constructor(uint256 when_) public {
      when = when_;
  }

  function burnByOwner(address account, uint256 amount) external onlyMinter {
    _burn(account, amount);
  }

}