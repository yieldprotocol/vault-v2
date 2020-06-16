pragma solidity ^0.6.2;

import "./interfaces/IVault.sol";
import "./interfaces/IWeth.sol";
import "./Constants.sol";
import "./UserProxy.sol";


/// @dev EthProxy allows users to post and withdraw Eth to the Dealer
contract EthProxy is UserProxy(), Constants {

    IWeth internal _weth;
    IVault internal _dealer;

    constructor (
        address payable weth_,
        address dealer_
    ) public {
        _weth = IWeth(weth_);
        _dealer = IVault(dealer_);
        _weth.approve(address(_dealer), uint(-1));
    }

    function postEth(address from, address to, uint256 amount)
        public payable onlyHolderOrProxy(from, "YDai: Only Holder Or Proxy") {
        _weth.deposit.value(amount)();      // Specify the ether in both `amount` and `value`
        _dealer.post(WETH, address(this), from, amount);
    }

    function withdrawEth(address from, address payable to, uint256 amount)
        public onlyHolderOrProxy(to, "YDai: Only Holder Or Proxy") {
        _dealer.withdraw(WETH, from, address(this), amount);
        _weth.withdraw(amount);
        to.transfer(amount);
    }
}