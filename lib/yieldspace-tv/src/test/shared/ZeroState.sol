// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;

import "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";

import {Exp64x64} from "../../Exp64x64.sol";
import {Math64x64} from "../../Math64x64.sol";
import {YieldMath} from "../../YieldMath.sol";

import "./Utils.sol";
import "./Constants.sol";
import {TestCore} from "./TestCore.sol";
import {SyncablePool} from "../mocks/SyncablePool.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {FYTokenMock} from "../mocks/FYTokenMock.sol";
import {YVTokenMock} from "../mocks/YVTokenMock.sol";
import {ETokenMock} from "../mocks/ETokenMock.sol";
import {EulerMock} from "../mocks/EulerMock.sol";
import {IERC20Like} from "../../interfaces/IERC20Like.sol";
import {ERC4626TokenMock} from "../mocks/ERC4626TokenMock.sol";
import {SyncablePoolNonTv} from "../mocks/SyncablePoolNonTv.sol";
import {SyncablePoolYearnVault} from "../mocks/SyncablePoolYearnVault.sol";
import {SyncablePoolEuler} from "../mocks/SyncablePoolEuler.sol";
import {AccessControl} from "@yield-protocol/utils-v2/src/access/AccessControl.sol";

bytes4 constant ROOT = 0x00000000;

struct ZeroStateParams {
    string assetName;
    string assetSymbol;
    uint8 assetDecimals;
    string sharesType;
    bool nonCompliant;
}

// ZeroState is the initial state of the protocol without any testable actions or state changes having taken place.
// Mocks are created, roles are granted, balances and initial prices are set.
// There is some complexity around sharesType ("4626" "EulerVault" "YearnVault").
// If sharesType is 4626:
//   - The shares token is a ERC4626TokenMock cast as IERC20Like.
//   - The pool is a SyncablePool.sol cast as ISyncablePool.
// If sharesType is YearnVault:
//   - The shares token is a YVTokenMock cast as IERC20Like.
//   - The pool is a SyncablePoolYearnVault.sol cast as ISyncablePool.
// If sharesType is Euler:
//   - The shares token is a ETokenMock cast as IERC20Like.
//   - The pool is a SyncablePoolEuler.sol cast as ISyncablePool.
// If sharesType is NonTv (not tokenized vault -- regular token):
//   - The shares token is is the base asset token cast as IERC20Like.
//   - The pool is a SyncablePoolNonTv.sol cast as ISyncablePool.
abstract contract ZeroState is TestCore {
    using Math64x64 for int128;
    using Math64x64 for uint256;

    constructor(ZeroStateParams memory params) {
        ts = ONE.div(uint256(25 * 365 * 24 * 60 * 60 * 10).fromUInt());

        // Set base asset state variables.
        assetName = params.assetName;
        assetSymbol = params.assetSymbol;
        assetDecimals = params.assetDecimals;
        nonCompliant = params.nonCompliant;
        // Create and set asset token.
        if(!nonCompliant) {
            asset = new ERC20Mock(assetName, assetSymbol, assetDecimals);
        } else {
            asset = ERC20Mock(0xdAC17F958D2ee523a2206206994597C13D831ec7);
        }

        // Set shares token related variables.
        if (keccak256(abi.encodePacked(params.sharesType)) == TYPE_NONTV) {
            sharesName = params.assetName;
            sharesSymbol = params.assetSymbol;
            sharesType = keccak256(abi.encodePacked(params.sharesType));
            sharesTypeString = params.sharesType;
        } else {
            sharesName = string.concat(params.sharesType, assetName);
            sharesSymbol = string.concat(params.sharesType, assetSymbol);
            sharesType = keccak256(abi.encodePacked(params.sharesType));
            sharesTypeString = params.sharesType;
        }

        // Set fyToken related variables.
        fySymbol = string.concat("fy", sharesSymbol);
        fyName = string.concat("fyToken ", sharesName, " maturity 1");

        sharesDecimals = assetDecimals;
        if (keccak256(abi.encodePacked(params.sharesType)) == TYPE_EULER) {
            sharesDecimals = 18;
        }

        // Set some state variables based on decimals, to use as constants.
        aliceSharesInitialBalance = 1000 * 10**(sharesDecimals);
        bobSharesInitialBalance = 2_000_000 * 10**(sharesDecimals);

        initialShares = 1_100_000 * 10**(sharesDecimals);
        initialFYTokens = 1_500_000 * 10**(assetDecimals);
    }

    function setUp() public virtual {
        // Create shares token (e.g. yvDAI)
        if (sharesType == TYPE_NONTV) {
            shares = IERC20Like(address(asset));
        } else {
            if (sharesType == TYPE_4626) {
                shares = IERC20Like(
                    address(new ERC4626TokenMock(sharesName, sharesSymbol, assetDecimals, address(asset)))
                );
            }
            if (sharesType == TYPE_YV) {
                shares = IERC20Like(address(new YVTokenMock(sharesName, sharesSymbol, assetDecimals, address(asset))));
            }
            if (sharesType == TYPE_EULER) {
                EulerMock euler = new EulerMock();
                shares = IERC20Like(address(new ETokenMock(sharesName, sharesSymbol, address(euler), address(asset))));
            }
            setPrice(address(shares), (muNumerator * (10**sharesDecimals)) / muDenominator);
            deal(address(asset), address(shares), 500_000_000 * 10**assetDecimals); // this is the vault reserves
        }

        // Create fyToken (e.g. "fyDAI").
        fyToken = new FYTokenMock(fyName, fySymbol, address(asset), maturity);

        // Setup users, and give them some shares.
        alice = address(0xbabe);
        vm.label(alice, "alice");
        shares.mint(alice, aliceSharesInitialBalance);
        fyToken.mint(alice, 50_000_000 * 10**assetDecimals);
        deal(address(asset), address(alice), 100_000_000 * 10**assetDecimals);
        bob = address(0xb0b);
        vm.label(bob, "bob");
        shares.mint(bob, bobSharesInitialBalance);
        fyToken.mint(bob, 50_000 * 10**assetDecimals);

        // Setup pool and grant roles:
        if (sharesType == TYPE_4626) {
            pool = new SyncablePool(address(shares), address(fyToken), ts, g1Fee);
        }
        if (sharesType == TYPE_YV) {
            pool = new SyncablePoolYearnVault(address(shares), address(fyToken), ts, g1Fee);
        }
        if (sharesType == TYPE_EULER) {
            EulerMock euler = ETokenMock(address(shares)).euler(); // Will work as long as there is only one ETokenMock contract
            pool = new SyncablePoolEuler(address(euler), address(shares), address(fyToken), ts, g1Fee);
        }
        if (sharesType == TYPE_NONTV) {
            pool = new SyncablePoolNonTv(address(shares), address(fyToken), ts, g1Fee);
        }
        // Alice: init
        AccessControl(address(pool)).grantRole(bytes4(pool.init.selector), alice);
        // Bob  : setFees.
        AccessControl(address(pool)).grantRole(bytes4(pool.setFees.selector), bob);
    }
}
