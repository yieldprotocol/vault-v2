// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

// https://github.com/makerdao/dss-cdp-manager/blob/master/src/GetCdps.sol
interface GetCdpsAbstract {
    function getCdpsAsc(address, address) external view returns (uint256[] memory, address[] memory, bytes32[] memory);
    function getCdpsDesc(address, address) external view returns (uint256[] memory, address[] memory, bytes32[] memory);
}
