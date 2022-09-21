// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "../LadleStorage.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";

contract RepayCloseModule is LadleStorage {
    using CastU256I128 for uint256;
    using CastU256U128 for uint256;
    using TransferHelper for IERC20;

    ///@notice Creates a Healer module for the Ladle
    ///@param cauldron_ address of the Cauldron
    ///@param weth_ address of WETH
    constructor(ICauldron cauldron_, IWETH9 weth_) LadleStorage(cauldron_, weth_) {}

    function repayFromLadle(bytes12 vaultId_, address collateralReceiver, address remainderReceiver)
        external payable
        returns (uint256 repaid)
    {
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        DataTypes.Series memory series = getSeries(vault.seriesId);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        
        uint256 amount = series.fyToken.balanceOf(address(this));
        repaid = amount <= balances.art ? amount : balances.art;

        // Update accounting, burn fyToken and return collateral
        if (repaid > 0) {
            cauldron.pour(vaultId, -(repaid.i128()), -(repaid.i128()));
            series.fyToken.burn(address(this), repaid);
            IJoin ilkJoin = getJoin(vault.ilkId);
            ilkJoin.exit(collateralReceiver, repaid.u128());
        }

        // Return remainder
        if (amount - repaid > 0) IERC20(address(series.fyToken)).safeTransfer(remainderReceiver, amount - repaid);

    }

    function closeFromLadle(bytes12 vaultId_, address collateralReceiver, address remainderReceiver)
        external payable
        returns (uint256 repaid)
    {
        (bytes12 vaultId, DataTypes.Vault memory vault) = getVault(vaultId_);
        DataTypes.Series memory series = getSeries(vault.seriesId);
        DataTypes.Balances memory balances = cauldron.balances(vaultId);
        
        IERC20 base = IERC20(cauldron.assets(series.baseId));
        uint256 amount = base.balanceOf(address(this));
        uint256 debtInBase = cauldron.debtToBase(vault.seriesId, balances.art);
        uint128 repaidInBase = ((amount <= debtInBase) ? amount : debtInBase).u128();
        repaid = (repaidInBase == debtInBase) ? balances.art : cauldron.debtFromBase(vault.seriesId, repaidInBase);

        // Update accounting, join base and return collateral
        if (repaidInBase > 0) {
            cauldron.pour(vaultId, -(repaid.i128()), -(repaid.i128()));
            IJoin baseJoin = getJoin(series.baseId);
            base.safeTransfer(address(baseJoin), repaidInBase);
            baseJoin.join(address(this), repaidInBase);
            IJoin ilkJoin = getJoin(vault.ilkId);
            ilkJoin.exit(collateralReceiver, repaid.u128()); // repaid is the ink collateral released, and equal to the fyToken debt. repaidInBase is the value of the fyToken debt in base terms
        }

        // Return remainder
        if (amount - repaidInBase > 0) base.safeTransfer(remainderReceiver, amount - repaidInBase);

    }

    /// @dev Obtains a vault by vaultId from the Cauldron, and verifies that msg.sender is the owner
    /// If bytes(0) is passed as the vaultId it tries to load a vault from the cache
    function getVault(bytes12 vaultId_)
        internal view
        returns (bytes12 vaultId, DataTypes.Vault memory vault)
    {
        if (vaultId_ == bytes12(0)) { // We use the cache
            require (cachedVaultId != bytes12(0), "Vault not cached");
            vaultId = cachedVaultId;
        } else {
            vaultId = vaultId_;
        }
        vault = cauldron.vaults(vaultId);
    } 

    /// @dev Obtains a series by seriesId from the Cauldron, and verifies that it exists
    function getSeries(bytes6 seriesId)
        internal view returns(DataTypes.Series memory series)
    {
        series = cauldron.series(seriesId);
        require (series.fyToken != IFYToken(address(0)), "Series not found");
    }

    /// @dev Obtains a join by assetId, and verifies that it exists
    function getJoin(bytes6 assetId)
        internal view returns(IJoin join)
    {
        join = joins[assetId];
        require (join != IJoin(address(0)), "Join not found");
    }

}