// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

contract TestConstants {
    uint256 public constant WAD = 1e18;

    bytes6 public constant CHI = 0x434849000000;
    bytes6 public constant RATE = 0x524154450000;

    bytes6 public constant ETH = 0x303000000000;
    bytes6 public constant DAI = 0x303100000000;
    bytes6 public constant USDC = 0x303200000000;
    bytes6 public constant WBTC = 0x303300000000;
    bytes6 public constant WSTETH = 0x303400000000;
    bytes6 public constant STETH = 0x303500000000;
    bytes6 public constant LINK = 0x303600000000;
    bytes6 public constant ENS = 0x303700000000;
    bytes6 public constant YVDAI = 0x303800000000;
    bytes6 public constant YVUSDC = 0x303900000000;
    bytes6 public constant UNI = 0x313000000000;
    bytes6 public constant CVX3CRV = 0x313000000000;
    bytes6 public constant FRAX = 0x313800000000;
    bytes6 public constant RETH = 0xE03016000000;
    bytes6 public constant CRAB = 0x333800000000;
    bytes6 public constant OSQTH = 0x333900000000;

    bytes6 public constant FYETH2206 = bytes6("0006");
    bytes6 public constant FYDAI2206 = bytes6("0106");
    bytes6 public constant FYUSDC2206 = bytes6("0206");
    bytes6 public constant FYUSDC2209 = bytes6("0207");
    bytes6 public constant FYUSDC2212 = bytes6("0208");
    bytes6 public constant FYDAI2212 = bytes6("0108");

    uint32 public constant EOJUN22 = 1656039600;

    string public constant CI = "CI";
    string public constant RPC = "RPC";
    string public constant LOCALHOST = "LOCALHOST";
    string public constant MAINNET = "MAINNET";
    string public constant ARBITRUM = "ARBITRUM";
    string public constant HARNESS = "HARNESS";
    string public constant UNIT_TESTS = "UNIT_TESTS";
    string public constant MOCK = "MOCK";
    string public constant NETWORK = "NETWORK";

    string public constant TIMELOCK = "TIMELOCK";
    string public constant CAULDRON = "CAULDRON";
    string public constant LADLE = "LADLE";

    mapping (string => mapping (string => address)) public addresses;

    constructor() {
        addresses[MAINNET][TIMELOCK] = 0x3b870db67a45611CF4723d44487EAF398fAc51E3;
        addresses[MAINNET][CAULDRON] = 0xc88191F8cb8e6D4a668B047c1C8503432c3Ca867;
        addresses[MAINNET][LADLE] = 0x6cB18fF2A33e981D1e38A663Ca056c0a5265066A;
        addresses[ARBITRUM][TIMELOCK] = 0xd0a22827Aed2eF5198EbEc0093EA33A4CD641b6c;
        addresses[ARBITRUM][CAULDRON] = 0x23cc87FBEBDD67ccE167Fa9Ec6Ad3b7fE3892E30;
        addresses[ARBITRUM][LADLE] = 0x16E25cf364CeCC305590128335B8f327975d0560;
    }
}
