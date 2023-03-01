// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ILadle.sol";
import "./ICauldron.sol";
import "./DataTypes.sol";

interface IWitchGov {
    function point(bytes32 param, address value) external;
    function setLineAndLimit(
        bytes6 ilkId,
        bytes6 baseId,
        uint32 duration,
        uint64 vaultProportion,
        uint64 collateralProportion,
        uint128 max
    ) external;

    function setProtected(address owner, bool _protected) external;

    function setAuctioneerReward(uint256 auctioneerReward_) external;
}
