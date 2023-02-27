// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

// https://github.com/makerdao/mip21-toolkit/blob/master/src/jars/RwaJar.sol
interface RwaJarAbstract {
    function daiJoin() external view returns(address);
    function dai() external view returns(address);
    function chainlog() external view returns(address);
    function void() external;
    function toss(uint256) external;
}
