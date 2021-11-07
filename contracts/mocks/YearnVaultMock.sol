// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import "@yield-protocol/utils-v2/contracts/token/ERC20Permit.sol";

import "contracts/oracles/yearn/IYvToken.sol";


contract YearnVaultMock is ERC20Permit, IYvToken {
    uint256 public price; //return value of pricePerShare()

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals,
        uint256 pricePerShare_
    ) ERC20Permit(name, symbol, decimals) {
        setPrice(pricePerShare_);
    }

    function pricePerShare() external view override returns (uint256) {
        return price;
    }

    /// @notice use to set sharee price of mock
    /// @dev be sure to use correct decimals
    function setPrice(uint256 price_) public {
        price = price_;
    }

    /// @dev Give tokens to whoever asks for them.
    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}
