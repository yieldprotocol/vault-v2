// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "@yield-protocol/utils-v2/contracts/token/ERC20Permit.sol";
import "../DAIMock.sol";
import "./DelegableMock.sol";


contract V1FYDaiMock is ERC20Permit, DelegableMock  {

    DAIMock public immutable dai;
    uint256 public immutable maturity;

    constructor(
        DAIMock dai_,
        uint256 maturity_
    ) ERC20Permit("FYDai", "FYDai", 18) {
        dai = dai_;
        maturity = maturity_;
    }

    /// @dev Give tokens to whoever asks for them.
    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }

    function redeem(address from, address to, uint256 amount)
        public
        onlyHolderOrDelegate(from, "FYDai: Only Holder Or Delegate")
        returns(uint256)
    {
        _burn(from, amount);
        dai.mint(to, amount);
        return amount;
    }
}
