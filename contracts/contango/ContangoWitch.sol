// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "../Witch.sol";
import "./interfaces/IContangoCauldron.sol";

contract ContangoWitch is Witch {
    constructor(IContangoCauldron cauldron_, ILadle ladle_) Witch(cauldron_, ladle_) {}

    // @dev check the aggregate of all vaults status
    function _isVaultUndercollateralised(bytes12) internal override returns (bool) {
        return IContangoCauldron(address(cauldron)).getFreeCollateralUSD() < 0;
    }
}
