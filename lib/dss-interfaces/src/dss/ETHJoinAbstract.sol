// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

// https://github.com/makerdao/dss/blob/master/src/join.sol
interface ETHJoinAbstract {
    function wards(address) external view returns (uint256);
    function rely(address usr) external;
    function deny(address usr) external;
    function vat() external view returns (address);
    function ilk() external view returns (bytes32);
    function live() external view returns (uint256);
    function cage() external;
    function join(address) external payable;
    function exit(address, uint256) external;
}
