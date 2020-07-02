pragma solidity ^0.6.2;

import "../interfaces/IDealer.sol";
import "../interfaces/IWeth.sol";
import "../helpers/Constants.sol";
import "../helpers/Delegable.sol";


/// @dev EthProxy allows users to post and withdraw Eth to the Dealer
contract EthProxy is Delegable(), Constants {

    IWeth internal _weth;
    IDealer internal _dealer;

    constructor (
        address payable weth_,
        address dealer_
    ) public {
        _weth = IWeth(weth_);
        _dealer = IDealer(dealer_);
        _weth.approve(address(_dealer), uint(-1));
    }

    receive() external payable { }

    function post(address from, address to, uint256 amount)
        public payable onlyHolderOrDelegate(from, "EthProxy: Only Holder Or Delegate") {
        _weth.deposit.value(amount)();      // Specify the ether in both `amount` and `value`
        _dealer.post(WETH, address(this), to, amount);
    }

    function withdraw(address from, address payable to, uint256 amount)
        public onlyHolderOrDelegate(from, "EthProxy: Only Holder Or Delegate") {
        _dealer.withdraw(WETH, from, address(this), amount);
        _weth.withdraw(amount);
        to.transfer(amount);
    }
}