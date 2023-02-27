// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

// https://github.com/makerdao/sai/blob/master/src/top.sol
interface SaiTopAbstract {
    function vox() external view returns (address);
    function tub() external view returns (address);
    function tap() external view returns (address);
    function sai() external view returns (address);
    function sin() external view returns (address);
    function skr() external view returns (address);
    function gem() external view returns (address);
    function fix() external view returns (uint256);
    function fit() external view returns (uint256);
    function caged() external view returns (uint256);
    function cooldown() external view returns (uint256);
    function era() external view returns (uint256);
    function cage() external;
    function flow() external;
    function setCooldown(uint256) external;
    function authority() external view returns (address);
    function owner() external view returns (address);
    function setOwner(address) external;
    function setAuthority(address) external;
}
