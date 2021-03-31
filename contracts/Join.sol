// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/utils/contracts/token/IERC20.sol";
import "@yield-protocol/vault-interfaces/IJoin.sol";
import "./AccessControl.sol";
import "./TransferHelper.sol";


library RMath { // Fixed point arithmetic in Ray units
    /// @dev Multiply an amount by a fixed point factor in ray units, returning an amount
    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            z = x * y / 1e27;
            require (z <= type(uint256).max, "RMUL Overflow");
        }
    }
}

library Safe256 {
    /// @dev Safely cast an uint256 to an uint128
    function u128(uint256 x) internal pure returns (uint128 y) {
        require (x <= type(uint128).max, "Cast overflow");
        y = uint128(x);
    }
}

interface IERC20Extended is IERC20 {
    function decimals() external returns (uint256);
}

contract Join is IJoin, IERC3156FlashLender, AccessControl() {
    using TransferHelper for IERC20;
    using RMath for uint256;
    using Safe256 for uint256;

    event FlashFeeFactorSet(uint256 indexed fee);

    bytes32 constant internal FLASH_LOAN_RETURN = keccak256("ERC3156FlashBorrower.onFlashLoan");

    address public immutable override asset;    // Underlying token contract
    uint8   public immutable decimals;          // Decimals on the token contract
    uint256 public storedBalance;
    uint256 public flashFeeFactor;              // Fee on flash loans, as a percentage in fixed point with 27 decimals (RAY)
    // uint    public live;  // Active Flag

    constructor(address asset_) {
        asset = asset_;
        decimals = uint8(IERC20Extended(asset_).decimals()); // TODO: Safely cast
        // live = 1;
    }

    /*
    function cage() external auth {
        live = 0;
    }
    */

    /// @dev Set the flash loan fee factor
    function setFlashFeeFactor(uint256 flashFeeFactor_)
        public
        auth
    {
        flashFeeFactor = flashFeeFactor_;
        emit FlashFeeFactorSet(flashFeeFactor_);
    }

    /// @dev Take assets from `user` using `transferFrom`, minus any unaccounted `asset` in this contract.
    /// `amount` is normalized to 18 decimals, so to join 1 USDC (6 decimals) you need to call `join(user, 1e18)`, not `join(user, 1e6)`. 
    function join(address user, uint128 amount)
        external override
        auth
        returns (uint128)
    {
        return _join(user, amount);
    }

    /// @dev Take assets from `user` using `transferFrom`, minus any unaccounted `asset` in this contract.
    /// `amount` is normalized to 18 decimals, so to join 1 USDC (6 decimals) you need to call `join(user, 1e18)`, not `join(user, 1e6)`. 
    function _join(address user, uint128 amount)
        internal
        returns (uint128)
    {
        uint128 assetAmount;                                     // Amount according to `asset` decimals
        if (decimals == 18) assetAmount = amount;
        else assetAmount = decimals > 18
            ? amount * (uint128(10) ** (decimals - 18))
            : amount / (uint128(10) ** (18 - decimals));
        
        IERC20 token = IERC20(asset);
        uint256 initialBalance = token.balanceOf(address(this));
        uint256 surplus = initialBalance - storedBalance;       // If you join assets with more than 18 decimals, you will lose the assets beyond the 18th decimal
        uint256 required = surplus >= assetAmount ? 0 : assetAmount - surplus;
        storedBalance = initialBalance + required;
        if (required > 0) token.safeTransferFrom(user, address(this), required);

        return assetAmount;
    }

    /// @dev Transfer assets to `user`
    /// `amount` is normalized to 18 decimals, so to exit 1 USDC (6 decimals) you need to call `exit(user, 1e18)`, not `exit(user, 1e6)`.
    function exit(address user, uint128 amount)
        external override
        auth
        returns (uint128)
    {
        return _exit(user, amount);
    }

    /// @dev Transfer assets to `user`
    /// `amount` is normalized to 18 decimals, so to exit 1 USDC (6 decimals) you need to call `exit(user, 1e18)`, not `exit(user, 1e6)`.
    function _exit(address user, uint128 amount)
        internal
        returns (uint128)
    {
        uint128 assetAmount;                                     // Amount according to `asset` decimals
        if (decimals == 18) assetAmount = amount;
        else assetAmount = decimals > 18
            ? amount * (uint128(10) ** (decimals - 18))
            : amount / (uint128(10) ** (18 - decimals));

        IERC20 token = IERC20(asset);
        
        storedBalance -= assetAmount;                                  // To withdraw surplus tokens we can do a `join` for zero tokens first.
        token.safeTransfer(user, assetAmount);
        
        return assetAmount;
    }

    /**
     * @dev From ERC-3156. The amount of currency available to be lended.
     * @param token The loan currency. It must be a FYDai contract.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) public view override returns (uint256) {
        return token == asset ? storedBalance : 0;
    }

    /**
     * @dev From ERC-3156. The fee to be charged for a given loan.
     * @param token The loan currency. It must be the asset.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 amount) public view override returns (uint256) {
        require(token == asset, "Unsupported currency");
        return _flashFee(amount);
    }

    /**
     * @dev The fee to be charged for a given loan.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function _flashFee(uint256 amount) internal view returns (uint256) {
        return amount.rmul(flashFeeFactor);
    }

    /**
     * @dev From ERC-3156. Loan `amount` `asset` to `receiver`, which needs to return them plus fee to this contract within the same transaction.
     * If the principal + fee are transferred to this contract, they won't be pulled from the receiver.
     * @param receiver The contract receiving the tokens, needs to implement the `onFlashLoan(address user, uint256 amount, uint256 fee, bytes calldata)` interface.
     * @param token The loan currency. Must be a fyDai contract.
     * @param amount The amount of tokens lent.
     * @param data A data parameter to be passed on to the `receiver` for any custom use.
     */
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes memory data) public override returns(bool) {
        require(token == asset, "Unsupported currency");
        uint128 _amount = amount.u128();
        uint128 _fee = _flashFee(amount).u128();
        _exit(address(receiver), _amount);

        require(receiver.onFlashLoan(msg.sender, token, _amount, _fee, data) == FLASH_LOAN_RETURN, "Non-compliant borrower");

        _join(address(receiver), _amount + _fee);
        return true;
    }
}