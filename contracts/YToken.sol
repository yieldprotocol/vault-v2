pragma solidity ^0.5.2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";


contract YToken is ERC20 {
    IERC20 public underlying;
    uint256 public maturity;

    constructor(address underlying_, uint256 maturity_) public {
        underlying = IERC20(underlying_);
        maturity = maturity_;
    }

    /// @dev Mint yTokens by posting an equal amount of underlying.
    function mint(address account, uint256 amount) public returns (bool) {
        // If we need to track the amount of posted underlying it can be done using totalSupply(), for now
        require(
            underlying.transferFrom(msg.sender, address(this), amount) == true,
            "YToken: Did not receive"
        );
        _mint(account, amount);
        return true;
    }

    /// @dev Burn yTokens and return an equal amount of underlying.
    function burn(uint256 amount) public returns (bool) {
        _burn(msg.sender, amount);
        require(
            underlying.transfer(msg.sender, amount) == true,
            "YToken: Did not refund"
        );
        return true;
    }
}
