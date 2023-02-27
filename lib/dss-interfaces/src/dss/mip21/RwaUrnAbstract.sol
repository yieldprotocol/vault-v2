// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

// https://github.com/makerdao/mip21-toolkit/blob/master/src/urns/RwaUrn.sol
// https://github.com/makerdao/mip21-toolkit/blob/master/src/urns/RwaUrn2.sol
interface RwaUrnAbstract {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function deny(address) external;
    function can(address) external view returns (uint256);
    function hope(address) external;
    function nope(address) external;
    function vat() external view returns (address);
    function jug() external view returns (address);
    function gemJoin() external view returns (address);
    function daiJoin() external view returns (address);
    function outputConduit() external view returns (address);
    function file(bytes32, address) external;
    function lock(uint256) external;
    function draw(uint256) external;
    function wipe(uint256) external;
    function free(uint256) external;
    function quit() external;
}
