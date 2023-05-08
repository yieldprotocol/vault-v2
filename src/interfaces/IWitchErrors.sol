// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./DataTypes.sol";

interface IWitchErrors {
    // ==================== Errors ====================

    error VaultAlreadyUnderAuction(bytes12 vaultId, address witch);
    error VaultNotLiquidatable(bytes6 ilkId, bytes6 baseId);
    error AuctionIsCorrect(bytes12 vaultId);
    error AuctioneerRewardTooHigh(uint256 max, uint256 actual);
    error WitchIsDead();
    error CollateralLimitExceeded(uint256 current, uint256 max);
    error NotUnderCollateralised(bytes12 vaultId);
    error UnderCollateralised(bytes12 vaultId);
    error VaultNotUnderAuction(bytes12 vaultId);
    error NotEnoughBought(uint256 expected, uint256 got);
    error JoinNotFound(bytes6 id);
    error UnrecognisedParam(bytes32 param);
    error LeavesDust(uint256 remainder, uint256 min);
}