// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.15;

import "./ERC20Mock.sol";
import "@yield-protocol/utils-v2/src/token/ERC20Permit.sol";



contract FYTokenMock is ERC20Permit, Mintable {
    ERC20Mock public underlying;
    uint32 public maturity;

    constructor (
        string memory name_,
        string memory symbol_,
        address underlying_,
        uint32 maturity_
    )
        ERC20Permit(
            name_,
            symbol_,
            IERC20Metadata(underlying_).decimals()
    ) {
        underlying = ERC20Mock(underlying_);
        maturity = maturity_;
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }

    function redeem(address from, address to, uint256 amount) public {
        _burn(from, amount);
        underlying.mint(to, amount);
    }
}
