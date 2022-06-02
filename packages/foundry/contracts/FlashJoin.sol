// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/utils-v2/contracts/token/TransferHelper.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "./Join.sol";

contract FlashJoin is Join, IERC3156FlashLender {
    using WMul for uint256;
    using CastU256U128 for uint256;
    event FlashFeeFactorSet(uint256 indexed fee);

    bytes32 internal constant FLASH_LOAN_RETURN = keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint256 public constant FLASH_LOANS_DISABLED = type(uint256).max;

    uint256 public flashFeeFactor = FLASH_LOANS_DISABLED; // Fee on flash loans, as a percentage in fixed point with 18 decimals. Flash loans disabled by default.

    constructor(address asset_) Join(asset_) {}

    /// @dev Set the flash loan fee factor
    function setFlashFeeFactor(uint256 flashFeeFactor_) external auth {
        flashFeeFactor = flashFeeFactor_;
        emit FlashFeeFactorSet(flashFeeFactor_);
    }

    /**
     * @dev From ERC-3156. The amount of currency available to be lended.
     * @param token The loan currency. It must be a FYDai contract.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view override returns (uint256) {
        return token == asset ? storedBalance : 0;
    }

    /**
     * @dev From ERC-3156. The fee to be charged for a given loan.
     * @param token The loan currency. It must be the asset.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 amount) external view override returns (uint256) {
        require(token == asset, "Unsupported currency");
        return _flashFee(amount);
    }

    /**
     * @dev The fee to be charged for a given loan.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function _flashFee(uint256 amount) internal view returns (uint256) {
        return amount.wmul(flashFeeFactor);
    }

    /**
     * @dev From ERC-3156. Loan `amount` `asset` to `receiver`, which needs to return them plus fee to this contract within the same transaction.
     * If the principal + fee are transferred to this contract, they won't be pulled from the receiver.
     * @param receiver The contract receiving the tokens, needs to implement the `onFlashLoan(address user, uint256 amount, uint256 fee, bytes calldata)` interface.
     * @param token The loan currency. Must be a fyDai contract.
     * @param amount The amount of tokens lent.
     * @param data A data parameter to be passed on to the `receiver` for any custom use.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes memory data
    ) external override returns (bool) {
        require(token == asset, "Unsupported currency");
        uint128 _amount = amount.u128();
        uint128 _fee = _flashFee(amount).u128();
        _exit(address(receiver), _amount);

        require(
            receiver.onFlashLoan(msg.sender, token, _amount, _fee, data) == FLASH_LOAN_RETURN,
            "Non-compliant borrower"
        );

        _join(address(receiver), _amount + _fee);
        return true;
    }
}
