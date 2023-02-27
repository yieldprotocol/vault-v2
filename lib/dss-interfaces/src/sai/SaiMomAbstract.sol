// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

// https://github.com/makerdao/sai/blob/master/src/mom.sol
interface SaiMomAbstract {
    function tub() external view returns (address);
    function tap() external view returns (address);
    function vox() external view returns (address);
    function setCap(uint256) external;
    function setMat(uint256) external;
    function setTax(uint256) external;
    function setFee(uint256) external;
    function setAxe(uint256) external;
    function setTubGap(uint256) external;
    function setPip(address) external;
    function setPep(address) external;
    function setVox(address) external;
    function setTapGap(uint256) external;
    function setWay(uint256) external;
    function setHow(uint256) external;
    function authority() external view returns (address);
    function owner() external view returns (address);
    function setOwner(address) external;
    function setAuthority(address) external;
}
