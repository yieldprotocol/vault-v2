pragma solidity ^0.6.2;


interface IFlashMinter {
    function executeOnFlashMint(address to, uint256 yDaiAmount, bytes calldata data) external;
}