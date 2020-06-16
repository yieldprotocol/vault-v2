pragma solidity ^0.6.2;

import "./interfaces/IGasToken.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IWeth.sol";
import "./Constants.sol";
import "./UserProxy.sol";


/// @dev EthProxy allows users to post and withdraw Eth to the Dealer
contract EthProxy is UserProxy(), Constants {

    IWeth internal _weth;
    IGasToken internal _gasToken;
    IVault internal _dealer;

    constructor (
        address payable weth_,
        address gasToken_,
        address dealer_
    ) public {
        _weth = IWeth(weth_);
        _gasToken = IGasToken(gasToken_);
        _dealer = IVault(dealer_);
        _weth.approve(address(_dealer), uint(-1));
    }

    receive() external payable { }

    function post(address from, address to, uint256 amount)
        public payable onlyHolderOrProxy(from, "YDai: Only Holder Or Proxy") {
        _weth.deposit.value(amount)();      // Specify the ether in both `amount` and `value`
        _dealer.post(WETH, address(this), from, amount);
    }

    function withdraw(address from, address payable to, uint256 amount)
        public onlyHolderOrProxy(to, "YDai: Only Holder Or Proxy") {
        _dealer.withdraw(WETH, from, address(this), amount);
        _weth.withdraw(amount);
        to.transfer(amount);

        uint256 gasRefund = _gasToken.balanceOf(address(this));
        if (gasRefund > 0) {
            _gasToken.transfer(msg.sender, gasRefund);
        }
    }
}