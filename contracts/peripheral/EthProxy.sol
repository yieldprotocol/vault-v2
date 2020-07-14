pragma solidity ^0.6.10;

import "../interfaces/IController.sol";
import "../interfaces/IWeth.sol";
import "../helpers/Delegable.sol";


/// @dev EthProxy allows users to post and withdraw Eth to the Controller, which will be converted to and from Weth in the process.
contract EthProxy is Delegable() {

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
    function post(address from, address to, uint256 amount)
        public payable onlyHolderOrDelegate(from, "EthProxy: Only Holder Or Delegate") {
        _weth.deposit{ value: amount }();
        _controller.post(WETH, address(this), to, amount);
    }

    /// @dev Users wishing to withdraw their Weth as ETH from the Controller should use this function.
    /// Users must have called `controller.addDelegate(ethProxy.address)` to authorize EthProxy to act in their behalf.
    function withdraw(address from, address payable to, uint256 amount)
        public onlyHolderOrDelegate(from, "EthProxy: Only Holder Or Delegate") {
        _controller.withdraw(WETH, from, address(this), amount);
        _weth.withdraw(amount);
        to.transfer(amount);
    }
}