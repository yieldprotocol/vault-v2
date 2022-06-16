// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

contract TestConstants {
    uint256 public constant WAD = 1e18;

    bytes6 public constant CHI = 0x434849000000;
    bytes6 public constant RATE = 0x524154450000;

    bytes6 public constant ETH = 0x303000000000;
    bytes6 public constant DAI = 0x303100000000;
    bytes6 public constant USDC = 0x303200000000;
    bytes6 public constant WSTETH = 0x303400000000;
    bytes6 public constant STETH = 0x303500000000;
    bytes6 public constant YVDAI = 0x303800000000;
    bytes6 public constant YVUSDC = 0x303900000000;

    bytes6 public constant FYETH2206 = bytes6("0006");
    bytes6 public constant FYDAI2206 = bytes6("0106");
    bytes6 public constant FYUSDC2206 = bytes6("0206");

    uint32 public constant EOJUN22 = 1656039600;
}
