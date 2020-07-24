// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/IVat.sol";
import "../interfaces/IPot.sol";
import "../interfaces/IController.sol";
import "../interfaces/IMarket.sol";
import "../helpers/Delegable.sol";
import "@nomiclabs/buidler/console.sol";

/**
 * @dev The Controller manages collateral and debt levels for all users, and it is a major user entry point for the Yield protocol.
 * Controller keeps track of a number of yDai contracts.
 * Controller allows users to post and withdraw Chai and Weth collateral.
 * Any transactions resulting in a user weth collateral below dust are reverted.
 * Controller allows users to borrow yDai against their Chai and Weth collateral.
 * Controller allows users to repay their yDai debt with yDai or with Dai.
 * Controller integrates with yDai contracts for minting yDai on borrowing, and burning yDai on repaying debt with yDai.
 * Controller relies on Treasury for all other asset transfers.
 * Controller allows orchestrated contracts to erase any amount of debt or collateral for an user. This is to be used during liquidations or during unwind.
 * Users can delegate the control of their accounts in Controllers to any address.
 */
contract ControllerDai is Delegable() {
    using SafeMath for uint256;

    bytes32 public constant CHAI = "CHAI";
    bytes32 public constant WETH = "ETH-A";

    IVat internal _vat;
    IPot internal _pot;
    IController internal _controller;
    IMarket internal _market;

    constructor (
        address vat_,
        address pot_,
        address controller_,
        address market_
    ) public {
        _vat = IVat(vat_);
        _pot = IPot(pot_);
        _controller = IController(controller_);
        _market = IMarket(market_);
    }

    function borrowDaiForMaximumCollateral(bytes32 collateral, uint256 maturity, uint256 tokenAmount, uint256 daiAmount)
        public
        returns (uint256)
    {
        address from = msg.sender;
        address to = msg.sender;
        uint256 borrowedYDai = _market.buyDaiPreview(from, to, daiAmount);
        uint256 borrowedDai = _controller.InDai(collateral, maturity, yDaiAmount);
        uint256 requiredCollateral = daiToCollateral(collateral, borrowedDai);
        require (requiredCollateral <= tokenAmount);

        // The collateral for this borrow needs to have been posted beforehand
        _controller.borrow(collateral, maturity, from, to, borrowedYDai);
        _market.buyDaiPreview(from, to, daiAmount);
        return requiredCollateral;
    }
    function borrowMinimumDaiForCollateral(bytes32 collateral, uint256 maturity, uint256 tokenAmount, uint256 daiAmount)
        public
        returns (uint256)
    {
        address from = msg.sender;
        address to = msg.sender;

        uint256 borrowedDai = collateralToDai(collateral, tokenAmount); // This is actually debt in Dai, not redeemable
        uint256 borrowedYDai = inYDai(collateral, maturity, borrowedDai);
        // The collateral for this borrow needs to have been posted beforehand
        _controller.borrow(collateral, maturity, from, to, borrowedYDai);
        uint256 boughtDai = _market.sellYDai(from, to, borrowedYDai);
        require (boughtDai >= daiAmount);
        return boughtDai;
    }

    function repayDaiForMaximumCollateral(bytes32 collateral, uint256 maturity, uint256 tokenAmount, uint256 daiAmount)
        public
        returns (uint256)
    {
        address from = msg.sender;
        address to = msg.sender;
    }
    function repayMinimumDaiForCollateral(bytes32 collateral, uint256 maturity, uint256 tokenAmount, uint256 daiAmount)

    // TODO: Collapse the inDai(), inCollateral() and *Growth() functions.

    function daiToCollateral(bytes32 collateral, uint256 daiAmount) public returns (uint256) {
        if (collateral == WETH){
            (,, uint256 spot,,) = _vat.ilks(WETH);
            return divd(daiAmount, spot);
        } else if (collateral == CHAI) {
            uint256 chi = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
            return divd(daiAmount, chi);
        } else {
            revert("Controller: Unsupported collateral");
        }        
    }

    function collateralToDai(bytes32 collateral, uint256 tokenAmount) public returns (uint256) {
        if (collateral == WETH){
            (,, uint256 spot,,) = _vat.ilks(WETH);
            return muld(tokenAmount, spot);
        } else if (collateral == CHAI) {
            uint256 chi = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
            return muld(tokenAmount, chi);
        } else {
            revert("Controller: Unsupported collateral");
        }        
    }
}
