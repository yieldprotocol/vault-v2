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
    /// `to` needs to authorize treasury in vat with `_vat.hope(address(_treasury))`.
    function splitPosition(uint256 maturity, address from, address to) public {
        require(
            msg.sender == from,
            "Splitter: Only owner"
        );
        (uint256 weth, uint256 debt) = _vault.settle(maturity, from);
        _treasury.fork(to, weth, debt);            // Transfer weth and debt
    }

    /// @dev Moves weth from `from` in YDai to `to` in MakerDAO.
    /// `to` needs to authorize treasury in vat with `_vat.hope(address(_treasury))`.
    function splitCollateral(address from, address to, uint256 amount) public {
        require(
            msg.sender == from,
            "Splitter: Only owner"
        );
        _vault.grab(from, amount);
        _treasury.fork(to, amount, 0);
    }
}