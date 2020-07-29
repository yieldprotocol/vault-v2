// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "../interfaces/IController.sol";
import "../interfaces/IWeth.sol";


/// @dev EthProxy allows users to post and withdraw Eth to the Controller, which will be converted to and from Weth in the process.
contract EthProxy {

    bytes32 public constant WETH = "ETH-A";

    IWeth internal _weth;
    address internal _treasury;
    IController internal _controller;

    constructor (
        address payable weth_,
        address treasury_,
        address controller_
    ) public {
        _weth = IWeth(weth_);
        _controller = IController(controller_);
        _weth.approve(address(treasury_), uint(-1));
    }

    /// @dev The WETH9 contract will send ether to EthProxy on `_weth.withdraw` using this function.
    receive() external payable { }

    /// @dev Users use `post` in EthProxy to post ETH to the Controller, which will be converted to Weth here.
    /// Users must have called `controller.addDelegate(ethProxy.address)` to authorize EthProxy to act in their behalf.
    /// @param to Yield Vault to deposit collateral in.
    /// @param amount Amount of collateral to move.
    function post(address to, uint256 amount)
        public payable {
        _weth.deposit{ value: amount }();
        _controller.post(WETH, address(this), to, amount);
    }

    /// @dev Users wishing to withdraw their Weth as ETH from the Controller should use this function.
    /// Users must have called `controller.addDelegate(ethProxy.address)` to authorize EthProxy to act in their behalf.
    /// @param to Wallet to send Eth to.
    /// @param amount Amount of weth to move.
    function withdraw(address payable to, uint256 amount)
        public {
        _controller.withdraw(WETH, msg.sender, address(this), amount);
        _weth.withdraw(amount);
        to.transfer(amount);
    }
}