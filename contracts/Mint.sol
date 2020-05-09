pragma solidity ^0.6.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILender.sol";
import "./interfaces/ISaver.sol";
import "./interfaces/IYDai.sol";
import "./interfaces/IChai.sol";
import "@nomiclabs/buidler/console.sol";


contract Mint {
    ILender internal _lender;
    ISaver internal _saver;
    IERC20 internal _dai;
    IYDai internal _yDai;
    IChai internal _chai;

    constructor (
        address lender_,
        address saver_,
        address dai_,
        address yDai_,
        address chai_
    ) public {
        _lender = ILender(lender_);
        _saver = ISaver(saver_);
        _dai = IERC20(dai_);
        _yDai = IYDai(yDai_);
        _chai = IChai(chai_);
    }

    function mintNoDebt(address user, uint256 dai) public {
        _dai.transferFrom(user, address(this), dai); // Get the dai from user
        _dai.approve(address(_chai), dai);                 // Chai will take dai
        _chai.join(address(this), dai);                    // Give dai to Chai, take chai back
        uint256 chai = dai;                                // Convert dai amount to chai amount
        _chai.approve(address(_saver), chai);              // Saver will take chai
        _saver.join(address(this), chai);                  // Send chai to Saver
        _yDai.mint(user, dai);                       // Mint yDai to user
    }

    function mintDebt(address user, uint256 dai) public {
        _dai.transferFrom(user, address(this), dai); // Get the dai from user
        _dai.approve(address(_lender), dai);               // Lender will take the dai
        _lender.repay(address(this), dai);                 // Lender takes dai from Mint to repay debt
        _yDai.mint(user, dai);                       // Mint yDai to user
    }

    function redeemSavings(address user, uint256 dai) public {
        _yDai.burn(user, dai);                       // Burn yDai from user
        uint256 chai = dai;                                // Convert dai amount to chai amount
        _saver.exit(address(this), chai);                  // Take chai from Saver
        _chai.exit(address(this), dai);                    // Give dai to Chai, take chai back
        _dai.transfer(user, dai);                    // Give dai to user
    }

    function redeemNoSavings(address user, uint256 dai) public {
        _yDai.burn(user, dai);                       // Burn yDai from user
        _lender.borrow(user, dai);                   // Borrow Dai from Lender to user
    }

    /* function grab(uint256 dai) public {
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
    } */
}