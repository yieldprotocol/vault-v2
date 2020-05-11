pragma solidity ^0.6.2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/ISaver.sol";
import "./Constants.sol";
import "./ERC20Dealer.sol";


/// @dev A ChaiDealer takes chai as collateral and issues yDai. Chai is saved in the Saver.
contract ChaiDealer is ERC20Dealer {

    ISaver internal _saver;

    constructor (
        address saver_,
        address yDai_,
        address chai_,
        address chaiOracle_
    ) public ERC20Dealer(yDai_, chai_, chaiOracle_) {
        _saver = ISaver(saver_);
    }

    /// @dev Takes chai from `from` address and gives it to the Saver
    // from --- Chai ---> saver
    function post(address from, uint256 chai) public override {
        // TODO: Consider a require on super.post()
        super.post(from, chai);                // Grab chai and update posted
        _token.approve(address(_saver), chai); // Saver will take chai
        _saver.join(address(this), chai);      // Send chai to Saver
    }

    /// @dev Takes chai from Saver and gives it to `to` address
    // us --- Token ---> to
    function withdraw(address to, uint256 chai) public override {
        _saver.exit(address(this), chai);      // Take chai from Saver
        super.withdraw(to, chai);              // Check collateralization, send chai to user and update posted
        // TODO: Consider a require on super.withdraw()
    }
}