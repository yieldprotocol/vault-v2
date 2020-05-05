pragma solidity ^0.6.2;

import "./../Treasury.sol";


contract MockTreasury is Treasury {

    constructor (address weth_, address dai_, address wethJoin_, address daiJoin_, address vat_, address pot_)
        public Treasury(weth_, dai_, wethJoin_, daiJoin_, vat_, pot_){
    }

    function borrowDai(address receiver, uint256 amount) public {
        _borrowDai(receiver, amount);
    }

    function repayDai() public {
        _repayDai();
    }

    function lockDai() public {
        _lockDai();
    }

    function freeDai(uint256 amount) public {
        _freeDai(amount);
    }
}
