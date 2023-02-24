// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {Exp64x64} from "../../Exp64x64.sol";
import {Math64x64} from "../../Math64x64.sol";
import {YieldMath} from "../../YieldMath.sol";

import {Pool} from "../../Pool/Pool.sol";
import {ERC20} from "../../Pool/PoolImports.sol";
import {ISyncablePool} from "../mocks/ISyncablePool.sol";
import {FYTokenMock as FYToken} from "../mocks/FYTokenMock.sol";
import {IEToken} from "../../../src/interfaces/IEToken.sol";

import "./Utils.sol";
import "./Constants.sol";

// ForkTestCore
// - Initializes state variables.
// - Sets state variable vm for accessing cheat codes.
// - Declares events,
// - Declares constants.
// No new contracts are created
abstract contract ForkTestCore is Test {
    event FeesSet(uint16 g1Fee);

    event Liquidity(
        uint32 maturity,
        address indexed from,
        address indexed to,
        address indexed fyTokenTo,
        int256 shares,
        int256 fyTokens,
        int256 poolTokens
    );

    event Sync(uint112 sharesCached, uint112 fyTokenCached, uint256 cumulativeBalancesRatio);

    event Trade(uint32 maturity, address indexed from, address indexed to, int256 shares, int256 fyTokens);

    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;

    Pool public pool;
    ERC20 public asset;
    FYToken public fyToken;
    IEToken public shares;

    address public alice = address(0xbabe);
    address public bob = address(0xb0b);
    address public timelock = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
    address public ladle = 0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A;
}
