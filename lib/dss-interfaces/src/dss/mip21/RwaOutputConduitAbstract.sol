// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

interface RwaOutputConduitBaseAbstract {
    function wards(address) external view returns (uint256);
    function rely(address) external;
    function deny(address) external;
    function can(address) external view returns (uint256);
    function hope(address) external;
    function nope(address) external;
    function dai() external view returns (address);
    function to() external view returns (address);
    function pick(address) external;
    function push() external;
}

// https://github.com/makerdao/mip21-toolkit/blob/master/src/conduits/RwaOutputConduit.sol
interface RwaOutputConduitAbstract is RwaOutputConduitBaseAbstract {
    function gov() external view returns (address);
    function bud(address) external view returns (uint256);
    function kiss(address) external;
    function diss(address) external;
}

// https://github.com/makerdao/mip21-toolkit/blob/master/src/conduits/RwaOutputConduit2.sol
interface RwaOutputConduit2Abstract is RwaOutputConduitBaseAbstract {
    function may(address) external view returns (uint256);
    function mate(address) external;
    function hate(address) external;
}

// https://github.com/makerdao/mip21-toolkit/blob/master/src/conduits/RwaOutputConduit3.sol
interface RwaOutputConduit3Abstract is RwaOutputConduitBaseAbstract {
    function bud(address) external view returns (uint256);
    function kiss(address) external;
    function diss(address) external;
    function may(address) external view returns (uint256);
    function mate(address) external;
    function hate(address) external;
    function psm() external view returns (address);
    function gem() external view returns (address);
    function quitTo() external view returns (address);
    function file(bytes32, address) external;
    function push(uint) external;
    function quit() external;
    function quit(uint) external;
    function yank(address, address, uint256) external;
    function expectedGemAmt(uint256) external view returns (uint256);
    function requiredDaiWad(uint256) external view returns (uint256);
}
