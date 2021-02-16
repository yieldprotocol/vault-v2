// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/utils/contracts/token/IERC20.sol";


interface IJoin {
    // --- Auth ---
    function wards (address usr) external view returns (uint);
    function rely(address usr) external;
    function deny(address usr) external;

    function token() external view returns (IERC20);
    function ilk() external view returns (bytes6);
    function dec() external view returns (uint);
    function live() external view returns (uint);

    function cage() external;

    function join(address usr, int wad) external returns (int128);
}