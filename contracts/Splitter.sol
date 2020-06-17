pragma solidity ^0.6.2;

import "./Constants.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IDealer.sol";


/// @dev A splitter moves positions and weth collateral from Dealers (using the IDealer interface) to MakerDAO.
contract Splitter is Constants {
    ITreasury internal _treasury;
    IDealer internal _vault;

    constructor (address treasury_, address vault_) public {
        _treasury = ITreasury(treasury_);
        _vault = IDealer(vault_);
    }

    /// @dev Moves all WETH debt and collateral from `from` in YDai to `to` in MakerDAO.
    /// `to` needs to authorize treasury in vat with `_vat.hope(address(_treasury))`.
    function split(address from, address to) public {
        require(
            msg.sender == from,
            "Splitter: Only owner"
        );
        (uint256 weth, uint256 debt) = _vault.erase(WETH, from);
        _treasury.fork(to, weth, debt);            // Transfer weth and debt
    }
}