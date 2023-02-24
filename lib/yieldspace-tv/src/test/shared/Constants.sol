// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;

// constants
uint256 constant WAD = 1e18;
uint256 constant MAX = type(uint256).max;
uint256 constant THREE_MONTHS = uint256(3) * 30 * 24 * 60 * 60;

uint256 constant INITIAL_SHARES = 1_100_000;
uint256 constant INITIAL_YVDAI = 1_100_000 * 1e18;
uint256 constant INITIAL_EUSDC = 1_100_000 * 1e18;

// 64.64
int128 constant ONE = 0x10000000000000000;

bytes32 constant TYPE_4626 = keccak256(abi.encodePacked("4626"));
bytes32 constant TYPE_NONTV = keccak256(abi.encodePacked("NonTv"));
bytes32 constant TYPE_YV = keccak256(abi.encodePacked("YearnVault"));
bytes32 constant TYPE_EULER = keccak256(abi.encodePacked("EulerVault"));

address constant MAINNET_DAI_JUNE_2023_POOL = 0xC2a463278387e649eEaA5aE5076e283260B0B1bE;
address constant MAINNET_USDC_JUNE_2023_POOL = 0x06aaF385809c7BC00698f1E266eD4C78d6b8ba75;
address constant EULER_MAINNET = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
