// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

// https://github.com/makerdao/sai/blob/master/src/vox.sol
interface SaiVoxAbstract {
    function fix() external view returns (uint256);
    function how() external view returns (uint256);
    function tau() external view returns (uint256);
    function era() external view returns (uint256);
    function mold(bytes32, uint256) external;
    function par() external returns (uint256);
    function way() external returns (uint256);
    function tell(uint256) external;
    function tune(uint256) external;
    function prod() external;
    function authority() external view returns (address);
    function owner() external view returns (address);
    function setOwner(address) external;
    function setAuthority(address) external;
}
