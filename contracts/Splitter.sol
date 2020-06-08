pragma solidity ^0.6.2;

import "./interfaces/ITreasury.sol";
import "./interfaces/IVault.sol";


/// @dev A splitter moves positions and weth collateral from Dealers (using the IVault interface) to MakerDAO.
contract Splitter {
    ITreasury internal _treasury;
    IVault internal _vault;

    constructor (address treasury_, address vault_) public {
        _treasury = ITreasury(treasury_);
        _vault = IVault(vault_);
    }

    /// @dev Moves all debt for one series from `from` in YDai to `to` in MakerDAO.
    /// It also moves just enough weth from YDai to MakerDAO to enable the debt transfer.
    /// `to` needs to surround this call with `_vat.hope(address(_treasury))` and `_vat.nope(address(_treasury))`
    function split(uint256 maturity, address from, address to) public {
        require(
            msg.sender == from,
            "Splitter: Only owner"
        );
        (uint256 weth, uint256 debt) = _vault.settle(maturity, from);
        _treasury.fork(to, weth, debt);            // Transfer weth and debt
    }

    /// @dev Moves all weth from `from` in YDai to `to` in MakerDAO.
    /// Can only be called with no YDai debt.
    /// `to` needs to surround this call with `_vat.hope(address(_treasury))` and `_vat.nope(address(_treasury))`
    function split(address from, address to) public {
        require(
            msg.sender == from,
            "Splitter: Only owner"
        );
        uint256 weth = _vault.posted(from);
        _vault.grab(from, weth);
        _treasury.fork(to, weth, 0);
    }
}