pragma solidity ^0.6.10;


contract Constants {
    // Fixed point256 precisions from MakerDao
    uint8 constant public WAD = 18;
    uint8 constant public RAY = 27;
    uint8 constant public RAD = 45;

    bytes32 public constant WETH = "WETH"; // TODO: Upgrade to 0.6.9 and use immutable
    bytes32 public constant CHAI = "CHAI"; // TODO: Upgrade to 0.6.9 and use immutable
}