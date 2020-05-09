pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./YDai.sol"; // Fix interface
import "./interfaces/IChai.sol";
import "@nomiclabs/buidler/console.sol";


contract Mint {
    IERC20 internal _dai;
    YDai internal _yDai; // Fix interface
    IChai internal _chai;

    constructor (
        address dai_,
        address yDai_,
        address chai_
    ) public {
        _dai = IERC20(dai_);
        _yDai = YDai(yDai_); // Fix interface
        _chai = IChai(chai_);
    }

    function mint(uint256 dai) public {
        _dai.transferFrom(msg.sender, address(this), dai);
        _dai.approve(address(_chai), dai);
        _chai.join(address(this), dai);
        _yDai.mint(msg.sender, dai);
    }

    function redeem(uint256 dai) public {
        _yDai.transferFrom(msg.sender, address(this), dai);
        _yDai.burn(address(this), dai);
        _chai.exit(address(this), dai);
        _dai.transfer(msg.sender, dai);
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