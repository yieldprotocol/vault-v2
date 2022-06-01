// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "./ERC1155.sol"; // TODO: Move to yield-utils-v2
import "../../LadleStorage.sol";


/// @dev Module to allow the Ladle to transfer ERC1155 tokens
contract Transfer1155Module is LadleStorage {

    /// @dev We won't use these, but still we need them in the constructor to not be abstract.
    constructor (ICauldron cauldron, IWETH9 weth) LadleStorage(cauldron, weth) { }

    /// @dev Allow users to trigger an ERC1155 token transfer from themselves to a receiver through the ladle, to be used with batch
    function transfer1155(ERC1155 token, uint256 id, address receiver, uint128 wad, bytes memory data)
        external payable
    {
        require(tokens[address(token)], "Unknown token");
        token.safeTransferFrom(msg.sender, receiver, id, wad, data);
    }
}