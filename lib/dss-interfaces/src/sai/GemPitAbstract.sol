// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.5.12;

// https://github.com/makerdao/sai/blob/master/src/pit.sol
interface GemPitAbstract {
    function burn(address) external;
}
