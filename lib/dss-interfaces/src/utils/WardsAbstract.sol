// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

interface WardsAbstract {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function deny(address) external;
}
