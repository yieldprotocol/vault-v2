// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/utils-v2/src/token/ERC20Permit.sol";
import "@yield-protocol/utils-v2/src/token/SafeERC20Namer.sol";
import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "../interfaces/IJoin.sol";
import "../interfaces/IOracle.sol";
import "../constants/Constants.sol";
import { UUPSUpgradeable } from "openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract VYToken is IERC3156FlashLender, UUPSUpgradeable, AccessControl, ERC20Permit, Constants {
    using Math for uint256;
    using Cast for uint256;

    event Point(bytes32 indexed param, address value);
    event FlashFeeFactorSet(uint256 indexed fee);
    event Redeemed(address indexed holder, address indexed receiver, uint256 principalAmount, uint256 underlyingAmount);

    bool public initialized;

    bytes32 internal constant FLASH_LOAN_RETURN = keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint256 constant FLASH_LOANS_DISABLED = type(uint256).max;
    uint256 public flashFeeFactor = FLASH_LOANS_DISABLED; // Fee on flash loans, as a percentage in fixed point with 18 decimals. Flash loans disabled by default by overflow from `flashFee`.

    IOracle public immutable oracle; // Oracle for the savings rate.
    IJoin public immutable join; // Source of redemption funds.
    address public immutable underlying;
    bytes6 public immutable underlyingId; // Needed to access the oracle

    constructor(
        bytes6 underlyingId_,
        IOracle oracle_, // Underlying vs its interest-bearing version
        IJoin join_,
        string memory name,
        string memory symbol
    ) ERC20Permit(name, symbol, SafeERC20Namer.tokenDecimals(address(IJoin(join_).asset()))) {
        // The join asset is this vyToken's underlying, from which we inherit the decimals
        underlyingId = underlyingId_;
        join = join_;
        underlying = address(IJoin(join_).asset());
        oracle = oracle_;

        // See https://medium.com/immunefi/wormhole-uninitialized-proxy-bugfix-review-90250c41a43a
        initialized = true; // Lock the implementation contract
    }

    /// @dev Give the ROOT role and create a LOCK role with itself as the admin role and no members. 
    /// Calling setRoleAdmin(msg.sig, LOCK) means no one can grant that msg.sig role anymore.
    function initialize (address root_) public {
        require(!initialized, "Already initialized");
        initialized = true;             // On an uninitialized contract, no governance functions can be executed, because no one has permission to do so
        _grantRole(ROOT, root_);      // Grant ROOT
        _setRoleAdmin(LOCK, LOCK);      // Create the LOCK role by setting itself as its own admin, creating an independent role tree
        flashFeeFactor = FLASH_LOANS_DISABLED; // Flash loans disabled by default
    }

    /// @dev Allow to set a new implementation
    function _authorizeUpgrade(address newImplementation) internal override auth {}

    /// @dev Set the flash loan fee factor
    function setFlashFeeFactor(uint256 flashFeeFactor_) external auth {
        flashFeeFactor = flashFeeFactor_;
        emit FlashFeeFactorSet(flashFeeFactor_);
    }

    ///@dev Converts the amount of the principal to the underlying
    function convertToUnderlying(uint256 principalAmount) external returns (uint256 underlyingAmount) {
        return _convertToUnderlying(principalAmount);
    }

    ///@dev Converts the amount of the principal to the underlying
    function _convertToUnderlying(uint256 principalAmount) internal returns (uint256 underlyingAmount) {
        (uint256 chi, ) = oracle.get(underlyingId, CHI, 0); // The value returned is an accumulator, it doesn't need an input amount
        return principalAmount.wmul(chi);
    }

    ///@dev Converts the amount of the underlying to the principal
    function convertToPrincipal(uint256 underlyingAmount) external returns (uint256 principalAmount) {
        return _convertToPrincipal(underlyingAmount);
    }

    ///@dev Converts the amount of the underlying to the principal
    function _convertToPrincipal(uint256 underlyingAmount) internal returns (uint256 princpalAmount) {
        (uint256 chi, ) = oracle.get(underlyingId, CHI, 0); // The value returned is an accumulator, it doesn't need an input amount
        return underlyingAmount.wdivup(chi);
    }

    ///@dev returns the maximum redeemable amount for the address holder in terms of the principal
    function maxRedeem(address holder) external view returns (uint256 maxPrincipalAmount) {
        return _balanceOf[holder];
    }

    ///@dev returns the amount of underlying redeemable in terms of the principal
    function previewRedeem(uint256 principalAmount) external returns (uint256 underlyingAmount) {
        return _convertToUnderlying(principalAmount);
    }

    /// @dev Burn vyToken for an amount of principal that increases according to `chi`
    /// If `amount` is 0, the contract will redeem instead the vyToken balance of this contract. Useful for batches.
    function redeem(uint256 principalAmount, address receiver, address holder) external returns (uint256 underlyingAmount) {
        principalAmount = (principalAmount == 0) ? _balanceOf[address(this)] : principalAmount;
        _burn(holder, principalAmount);
        underlyingAmount = _convertToUnderlying(principalAmount);
        join.exit(receiver, underlyingAmount.u128());

        emit Redeemed(holder, receiver, principalAmount, underlyingAmount);
    }

    /// @dev Burn vyToken for an amount of principal that increases according to `chi`
    /// If `amount` is 0, the contract will redeem instead the vyToken balance of this contract. Useful for batches.
    function redeem(address receiver, uint256 principalAmount) external returns (uint256 underlyingAmount) {
        principalAmount = (principalAmount == 0) ? _balanceOf[address(this)] : principalAmount;
        _burn(msg.sender, principalAmount);
        underlyingAmount = _convertToUnderlying(principalAmount);
        join.exit(receiver, underlyingAmount.u128());

        emit Redeemed(msg.sender, receiver, principalAmount, underlyingAmount);
    }

    ///@dev returns the maximum withdrawable amount for the address holder in terms of the underlying
    function maxWithdraw(address holder) external returns (uint256 maxUnderlyingAmount) {
        return _convertToUnderlying(_balanceOf[holder]);
    }

    ///@dev returns the amount of the principal withdrawable in terms of the underlying
    function previewWithdraw(uint256 underlyingAmount) external returns (uint256 principalAmount) {
        return _convertToPrincipal(underlyingAmount);
    }

    /// @dev Burn vyToken for an amount of underlying that increases according to `chi`
    /// If `amount` is 0, the contract will redeem instead the vyToken balance of this contract. Useful for batches.
    function withdraw(uint256 underlyingAmount, address receiver, address holder) external returns (uint256 principalAmount) {
        principalAmount = (underlyingAmount == 0) ? _balanceOf[address(this)] : _convertToPrincipal(underlyingAmount);
        _burn(holder, principalAmount);
        underlyingAmount = _convertToUnderlying(principalAmount);
        join.exit(receiver, underlyingAmount.u128());

        emit Redeemed(holder, receiver, principalAmount, underlyingAmount);
    }

    /// @dev Mint vyTokens.
    function mint(address receiver, uint256 principalAmount) external auth {
        join.join(msg.sender, _convertToUnderlying(principalAmount).u128());
        _mint(receiver, principalAmount);
    }

    ///@dev returns the maximum mintable amount for the address holder in terms of the principal
    function maxMint(address) external view returns (uint256 maxPrincipalAmount) {
        return type(uint256).max - _totalSupply;
    }

    ///@dev returns the amount of the principal mintable in terms of the underlying
    function previewMint(uint256 principalAmount) external returns (uint256 underlyingAmount) {
        return _convertToUnderlying(principalAmount.u128());
    }

    /// @dev Mint vyTokens.
    function deposit(address receiver, uint256 underlyingAmount) external auth {
        join.join(msg.sender, underlyingAmount.u128());
        _mint(receiver, _convertToPrincipal(underlyingAmount));
    }

    ///@dev returns the maximum depositable amount for the address holder in terms of the underlying
    function maxDeposit(address) external returns (uint256 maxUnderlyingAmount) {
        return _convertToUnderlying(type(uint256).max - _totalSupply);
    }

    ///@dev returns the amount of the underlying depositable in terms of the principal
    function previewDeposit(uint256 underlyingAmount) external returns (uint256 principalAmount) {
        return _convertToPrincipal(underlyingAmount.u128());
    }

    /// @dev Burn vyTokens.
    /// Any tokens locked in this contract will be burned first and subtracted from the amount to burn from the user's wallet.
    /// This feature allows someone to transfer vyToken to this contract to enable a `burn`, potentially saving the cost of `approve` or `permit`.
    function _burn(address holder, uint256 principalAmount) internal override returns (bool) {
        // First use any tokens locked in this contract
        uint256 available = _balanceOf[address(this)];
        if (available >= principalAmount) {
            return super._burn(address(this), principalAmount);
        } else {
            if (available > 0) super._burn(address(this), available);
            unchecked {
                _decreaseAllowance(holder, principalAmount - available);
            }
            unchecked {
                return super._burn(holder, principalAmount - available);
            }
        }
    }

    /**
     * @dev From ERC-3156. The amount of currency available to be lended.
     * @param token The loan currency. It must be a VYToken contract.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view returns (uint256) {
        return token == address(this) ? type(uint256).max - _totalSupply : 0;
    }

    /**
     * @dev From ERC-3156. The fee to be charged for a given loan.
     * @param token The loan currency. It must be the asset.
     * @param principalAmount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 principalAmount) external view returns (uint256) {
        require(token == address(this), "Unsupported currency");
        return _flashFee(principalAmount);
    }

    /**
     * @dev The fee to be charged for a given loan.
     * @param principalAmount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function _flashFee(uint256 principalAmount) internal view returns (uint256) {
        return principalAmount.wmul(flashFeeFactor);
    }

    /**
     * @dev From ERC-3156. Loan `amount` vyDai to `receiver`, which needs to return them plus fee to this contract within the same transaction.
     * Note that if the initiator and the borrower are the same address, no approval is needed for this contract to take the principal + fee from the borrower.
     * If the borrower transfers the principal + fee to this contract, they will be burnt here instead of pulled from the borrower.
     * @param receiver The contract receiving the tokens, needs to implement the `onFlashLoan(address user, uint256 amount, uint256 fee, bytes calldata)` interface.
     * @param token The loan currency. Must be a vyDai contract.
     * @param principalAmount The amount of tokens lent.
     * @param data A data parameter to be passed on to the `receiver` for any custom use.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 principalAmount,
        bytes memory data
    ) external returns (bool) {
        require(token == address(this), "Unsupported currency");
        _mint(address(receiver), principalAmount);
        uint128 fee = _flashFee(principalAmount).u128();
        require(
            receiver.onFlashLoan(msg.sender, token, principalAmount, fee, data) == FLASH_LOAN_RETURN,
            "Non-compliant borrower"
        );
        _burn(address(receiver), principalAmount + fee);
        return true;
    }
}