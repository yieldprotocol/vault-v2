// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./ILadle.sol";

interface IWitch {
    /// @dev Link to the Cauldron in the Yield Protocol
    function cauldron() external returns (ICauldron);

    /// @dev Link to the Ladle in the Yield Protocol
    function ladle() external returns (ILadle);

    /// @dev Vaults up for liquidation
    function auctions(bytes12 vaultId)
        external
        returns (address owner, uint32 start);

    /// @dev Auction parameters per ilk
    function ilks(bytes6 ilkId)
        external
        returns (uint32 duration, uint64 initialOffer);

    /// @dev Pay all debt from a vault in liquidation, getting at least `min` collateral.
    function payAll(bytes12 vaultId, uint128 min)
        external
        returns (uint256 ink);
}
