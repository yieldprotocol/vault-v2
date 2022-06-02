// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "../../mocks/ERC20Mock.sol";
import "./ERC1155.sol"; // TODO: Move to yield-utils-v2
import "./IBatchAction.sol";

contract FCashMock is ERC1155 {
    using WMul for uint256;

    ERC20Mock public immutable underlying;
    uint256 public immutable fCashId;
    uint256 public accrual;

    constructor(ERC20Mock underlying_, uint256 fCashId_) {
        underlying = underlying_;
        fCashId = fCashId_;
    }

    function uri(uint256) public view virtual override returns (string memory) {
        return "";
    }

    function setAccrual(uint256 accrual_) external {
        accrual = accrual_;
    }

    function mint(
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) external {
        _mint(to, id, amount, data);
    }

    function batchBalanceAction(address account, IBatchAction.BalanceAction[] calldata actions) external {
        uint256 toBurn = balanceOf[account][fCashId];
        uint256 toMint = toBurn.wmul(accrual);
        _burn(account, fCashId, toBurn);
        underlying.mint(account, toMint);
    }
}