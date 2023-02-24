// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;
import "./ERC1155.sol"; // TODO: Move to yield-utils-v2

contract ERC1155Mock is ERC1155 {

    function uri(uint256) public view virtual override returns (string memory) {
        return "";
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external {
        _mint(to, id, amount, data);
    }
}