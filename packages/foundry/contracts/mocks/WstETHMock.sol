// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import '@yield-protocol/utils-v2/contracts/token/ERC20Permit.sol';

contract WstETHMock is ERC20Permit {
    ERC20 stETH;

    constructor(ERC20 _stETH) ERC20Permit('Wrapped liquid staked Ether 2.0', 'wstETH', 18) {
        stETH = _stETH;
    }

    function wrap(uint256 _stETHAmount) external returns (uint256) {
        uint256 wstETHAmount = _stETHAmount;
        _mint(msg.sender, wstETHAmount);
        stETH.transferFrom(msg.sender, address(this), _stETHAmount);
        return wstETHAmount;
    }

    function unwrap(uint256 _wstETHAmount) external returns (uint256) {
        uint256 stETHAmount = _wstETHAmount;
        _burn(msg.sender, _wstETHAmount);
        stETH.transfer(msg.sender, stETHAmount);
        return stETHAmount;
    }

    /// @dev Give tokens to whoever asks for them.
    function mint(address to, uint256 amount) public virtual {
        _mint(to, amount);
    }
}
