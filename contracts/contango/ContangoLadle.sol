// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;

import "../Ladle.sol";

contract ContangoLadle is Ladle {

    constructor (ICauldron cauldron, IWETH9 weth) Ladle(cauldron, weth) { }

    // @dev auth version of build, only contango can create vaults here
    // all other methods rely on being vault owner, so no need to secure them
    function build(bytes6 seriesId, bytes6 ilkId, uint8 salt)
        external override payable auth
        returns(bytes12, DataTypes.Vault memory)
    {
        return _build(seriesId, ilkId, salt);
    }

}