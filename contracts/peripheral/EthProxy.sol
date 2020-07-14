pragma solidity ^0.6.10;

import "../interfaces/IController.sol";
import "../interfaces/IWeth.sol";
import "../helpers/Delegable.sol";


/// @dev EthProxy allows users to post and withdraw Eth to the Controller
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

    receive() external payable { }

    function post(address from, address to, uint256 amount)
        public payable onlyHolderOrDelegate(from, "EthProxy: Only Holder Or Delegate") {
        _weth.deposit.value(amount)();      // Specify the ether in both `amount` and `value`
        _controller.post(WETH, address(this), to, amount);
    }

    function withdraw(address from, address payable to, uint256 amount)
        public onlyHolderOrDelegate(from, "EthProxy: Only Holder Or Delegate") {
        _controller.withdraw(WETH, from, address(this), amount);
        _weth.withdraw(amount);
        to.transfer(amount);
    }
}