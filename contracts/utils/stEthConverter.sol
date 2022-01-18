// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "../oracles/lido/IWstETH.sol";

/// @dev A contract to handle wrapping & unwrapping of stETH
contract stEthConverter {
    using TransferHelper for IERC20;
    using TransferHelper for IWstETH;

    IWstETH public immutable wstETH;
    IERC20 public immutable stETH;
    IERC20 public immutable underlying; // Compliance to ERC4626

    event Deposit(address from, address to, uint256 amount);
    event Withdraw(address from, address to, uint256 amount);

    constructor(IWstETH wstETH_, IERC20 stETH_) {
        wstETH = wstETH_;
        stETH = stETH_;
        stETH_.approve(address(wstETH_), type(uint256).max);

        underlying = stEth_;
    }

    /// @dev Total amount of stEth held by the wstEth contract
    function totalUnderlying() external view returns (uint256 value) {
        value = wstEth.getStEthByWstEth(address(wstEth));
    }

    /// @dev Value in stEth terms of the wstEth held by `owner`
    function balanceOfUnderlying(address owner) external view returns (uint256 value) {
        value = wstEth.getStEthByWstEth(wstEth.balanceOf(owner));
    }

    /// @dev Wrap stEth and forward it to the "to" address
    /// It will use any stEth held by this contract first, before pulling any extra needed.
    /// If this contract holds too much stEth, the surplus will be sent to the caller.
    function deposit(address to, uint256 value) external returns (uint256 shares) {
        // Bring in any stEth needed, or return any surplus
        uint256 valueHeld = stETH.balanceOf(address(this));
        if (value > valueHeld) stEth.safeTransferFrom(msg.sender, address(this), unchecked {valueHeld - value});
        if (value < valueHeld) stEth.safeTransfer(msg.sender, unchecked {value - valueHeld});

        shares = wstETH.wrap(value);
        wstETH.safeTransfer(to, shares);
        emit Deposit(msg.sender, to, value);
    }

    /// @dev Unwrap wstEth and forward it to the "to" address
    /// It will use any wstEth held by this contract first, before pulling any extra needed.
    /// If this contract holds too much wstEth, the surplus will be sent to the caller.
    function withdraw(address to, uint256 value) external returns (uint256 shares) {
        // Bring in any wstEth needed, or return any surplus
        shares = wstETH.getWstETHByStETH(value);
        uint256 sharesHeld = wstETH.balanceOf(address(this));
        if (shares > sharesHeld) wstEth.safeTransferFrom(msg.sender, address(this), unchecked {sharesHeld - shares});
        if (shares < sharesHeld) wstEth.safeTransfer(msg.sender, unchecked {shares - sharesHeld});

        value = wstETH.unwrap(shares);
        stETH.safeTransfer(to, value);
        emit Withdraw(msg.sender, to, value);
    }

    /// @dev Wrap stEth and forward it to the "to" address
    /// It will use any stEth held by this contract first, before pulling any extra needed.
    /// If this contract holds too much stEth, the surplus will be sent to the caller.
    function mint(address to, uint256 shares) external returns (uint256 value) {
        // Bring in any stEth needed, or return any surplus
        value = wstETH.getStETHByWstETH(shares);
        uint256 valueHeld = stETH.balanceOf(address(this));
        if (value > valueHeld) stEth.safeTransferFrom(msg.sender, address(this), unchecked {valueHeld - value});
        if (value < valueHeld) stEth.safeTransfer(msg.sender, unchecked {value - valueHeld});

        shares = wstETH.wrap(value);
        wstETH.safeTransfer(to, shares);
        emit Deposit(msg.sender, to, value);
    }

    /// @dev Unwrap wstEth and forward it to the "to" address
    /// It will use any wstEth held by this contract first, before pulling any extra needed.
    /// If this contract holds too much wstEth, the surplus will be sent to the caller.
    function redeem(address to, uint256 shares) external returns (uint256 value) {
        // Bring in any wstEth needed, or return any surplus
        uint256 sharesHeld = wstETH.balanceOf(address(this));
        if (shares > sharesHeld) wstEth.safeTransferFrom(msg.sender, address(this), unchecked {sharesHeld - shares});
        if (shares < sharesHeld) wstEth.safeTransfer(msg.sender, unchecked {shares - sharesHeld});

        value = wstETH.unwrap(shares);
        stETH.safeTransfer(to, value);
        emit Withdraw(msg.sender, to, value);
    }

    /// @dev Calculate how many shares would be obtained in a given deposit.
    function depositPreview(uint256 value) external returns (uint256 shares) {
        shares = wstETH.getWstETHByStETH(value);
    }

    /// @dev Calculate how much underlying would be obtained in a given withdraw.
    function withdrawPreview(uint256 value) external returns (uint256 shares) {
        shares = wstETH.getWstETHByStETH(value);
    }

    /// @dev Calculate how much underlying would be needed for a given mint.
    function mintPreview(uint256 shares) external returns (uint256 value) {
        value = wstETH.getStETHByWstETH(value);
    }

    /// @dev Calculate how many underlying would be needed for a given redeem.
    function redeemPreview(uint256 shares) external returns (uint256 value) {
        value = wstETH.getStETHByWstETH(value);
    }
}