// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import "@yield-protocol/utils-v2/contracts/token/IERC1155.sol";
import "../LadleStorage.sol";


/// @dev Module to allow the Ladle to transfer ERC1155 tokens
contract Transfer1155Module is LadleStorage {
    /// @dev Allow users to trigger an ERC1155 token transfer from themselves to a receiver through the ladle, to be used with batch
    function transfer1155(IERC1155 token, uint256 id, address receiver, uint128 wad, bytes memory data)
        external payable
    {
        require(tokens[address(token)], "Unknown token");
        token.safeTransferFrom(msg.sender, receiver, wad, id, data);
    }
}