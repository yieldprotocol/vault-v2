pragma solidity ^0.6.2;

import "../Splitter.sol";


/// @dev A splitter moves positions and weth collateral from Dealers (using the IVault interface) to MakerDAO.
contract MockSplitter is Splitter {
    constructor (address treasury_, address vault_)
        public Splitter(treasury_, vault_ ){ }

    /// @dev Moves all debt for one series from `from` in YDai to `to` in MakerDAO.
    /// It also moves just enough weth from YDai to MakerDAO to enable the debt transfer.
    /// `to` needs to surround this call with `_vat.hope(address(_treasury))` and `_vat.nope(address(_treasury))`
    function splitPosition(uint256 maturity, address from, address to) public {
        split(maturity, from, to);
    }

    /// @dev Moves all weth from `from` in YDai to `to` in MakerDAO.
    /// Can only be called with no YDai debt.
    /// `to` needs to surround this call with `_vat.hope(address(_treasury))` and `_vat.nope(address(_treasury))`
    function splitCollateral(address from, address to) public {
        split(from, to);
    }
}