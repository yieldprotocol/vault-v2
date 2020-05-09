pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IChai.sol";
import "@nomiclabs/buidler/console.sol";


contract Test {
    IERC20 internal _dai;
    IChai internal _chai;

    constructor (
        address dai_,
        address chai_
    ) public {
        _dai = IERC20(dai_);
        _chai = IChai(chai_);
    }

    function grab(uint256 dai) public {
        _dai.transferFrom(msg.sender, address(this), dai);
    }

    function toChai(uint256 dai) public {
        _dai.approve(address(_chai), dai);
        _chai.join(address(this), dai);
    }

    function toDai(uint256 dai) public {
        _chai.exit(address(this), dai);
    }

    function spit(uint256 dai) public {
        _dai.transfer(msg.sender, dai);
    }
}