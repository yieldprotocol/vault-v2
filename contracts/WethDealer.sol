pragma solidity ^0.6.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ILender.sol";
import "./Constants.sol";
import "./Dealer.sol";


/// @dev A WethDealer takes weth as collateral and issues yDai. Weth is posted to MakerDAO through the Lender.
contract ChaiDealer is Dealer {

    ILender internal _lender;

    constructor (
        address lender_,
        address yDai_,
        address chai_,
        address chaiOracle_
    ) public Dealer(yDai_, chai_, chaiOracle_) {
        _lender = ILender(lender_);
    }

    /// @dev Takes weth from `from` address and posts it to the Lender
    // from --- Weth ---> lender
    function post(address from, uint256 weth) public override {
        // TODO: Consider a require on super.post()
        super.post(from, weth);                 // Grab weth and update posted
        _token.approve(address(_lender), weth); // Lender will take weth
        _lender.post(address(this), weth);      // Post weth to Lender
    }

    /// @dev Takes weth from Lender and gives it to `to` address
    // us --- Token ---> to
    function withdraw(address to, uint256 weth) public override {
        _lender.withdraw(address(this), weth);  // Take weth from Lender
        super.withdraw(to, weth);               // Check collateralization, send chai to user and update posted
        // TODO: Consider a require on super.withdraw()
    }
}