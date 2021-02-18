// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";


interface IJoin {
    /// @dev ERC20 token managed by this contract
    function token() external view returns (IERC20);

    /// @dev Add tokens to this contract.
    /// Or, if wad is negative, remove tokens from this contract.
    function join(address user, int128 wad) external returns (int128);
}