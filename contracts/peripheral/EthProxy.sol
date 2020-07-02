pragma solidity ^0.6.2;

import "../interfaces/IGasToken.sol";
import "../interfaces/IDealer.sol";
import "../interfaces/IWeth.sol";
import "../helpers/Constants.sol";
import "../helpers/Delegable.sol";


/// @dev EthProxy allows users to post and withdraw Eth to the Dealer
contract EthProxy is Delegable(), Constants {

    IWeth internal _weth;
    IGasToken internal _gasToken;
    IDealer internal _dealer;

    constructor (
        address payable weth_,
        address gasToken_,
        address treasury_,
        address dealer_
    ) public {
        _weth = IWeth(weth_);
        _gasToken = IGasToken(gasToken_);
        _dealer = IDealer(dealer_);
        // TODO: Fix for migrations
        _weth.approve(treasury_, uint(-1));
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

        uint256 gasRefund = _gasToken.balanceOf(address(this));
        if (gasRefund > 0) {
            _gasToken.transfer(msg.sender, gasRefund);
        }
    }
}