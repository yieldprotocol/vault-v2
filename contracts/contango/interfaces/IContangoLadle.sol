// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@yield-protocol/vault-interfaces/src/ILadle.sol";

interface IContangoLadle is ILadle {
    function deterministicBuild(
        bytes12 vaultId,
        bytes6 seriesId,
        bytes6 ilkId
    ) external returns (DataTypes.Vault memory vault);
}
