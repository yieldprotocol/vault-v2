// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "../../Ladle.sol";

contract ContangoLadle is Ladle {
    constructor(ICauldron cauldron, IWETH9 weth) Ladle(cauldron, weth) {}

    // @dev we want to use deterministic vault creation given is behind auth
    function build(
        bytes6,
        bytes6,
        uint8
    ) external payable override returns (bytes12, DataTypes.Vault memory) {
        revert("Use deterministicBuild");
    }

    // @dev deterministic version of build, only contango can create vaults here
    // all other methods rely on being vault owner, so no need to secure them
    function deterministicBuild(
        bytes12 vaultId,
        bytes6 seriesId,
        bytes6 ilkId
    ) external payable auth returns (DataTypes.Vault memory vault) {
        vault = cauldron.build(msg.sender, vaultId, seriesId, ilkId);
    }
}
