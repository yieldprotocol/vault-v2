// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./DataTypes.sol";

interface IWitchEvents {
    // ==================== User events ====================

    event Auctioned(
        bytes12 indexed vaultId,
        DataTypes.Auction auction,
        uint256 duration,
        uint256 initialCollateralProportion
    );
    event Cancelled(bytes12 indexed vaultId);
    event Cleared(bytes12 indexed vaultId);
    event Ended(bytes12 indexed vaultId);
    event Bought(
        bytes12 indexed vaultId,
        address indexed buyer,
        uint256 ink,
        uint256 art
    );

    // ==================== Governance events ====================

    event Point(
        bytes32 indexed param,
        address indexed oldValue,
        address indexed newValue
    );
    event LineSet(
        bytes6 indexed ilkId,
        bytes6 indexed baseId,
        uint32 duration,
        uint64 vaultProportion,
        uint64 collateralProportion
    );
    event LimitSet(bytes6 indexed ilkId, bytes6 indexed baseId, uint128 max);
    event ProtectedSet(address indexed value, bool protected);
    event AuctioneerRewardSet(uint256 auctioneerReward);
}