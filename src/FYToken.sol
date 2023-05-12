// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/utils-v2/src/token/ERC20Permit.sol";
import "@yield-protocol/utils-v2/src/token/SafeERC20Namer.sol";
import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "./interfaces/IFYToken.sol";
import "./interfaces/IJoin.sol";
import "./interfaces/IOracle.sol";
import "./constants/Constants.sol";

contract FYToken is IFYToken, IERC3156FlashLender, AccessControl, ERC20Permit, Constants {
    using Math for *;
    using Cast for *;

    event Point(bytes32 indexed param, address value);
    event FlashFeeFactorSet(uint256 indexed fee);
    event SeriesMatured(uint256 chiAtMaturity);
    event Redeemed(address indexed holder, address indexed receiver, uint256 principalAmount, uint256 underlyingAmount);

    uint256 constant CHI_NOT_SET = type(uint256).max;

    uint256 internal constant MAX_TIME_TO_MATURITY = 126144000; // seconds in four years
    bytes32 internal constant FLASH_LOAN_RETURN = keccak256("ERC3156FlashBorrower.onFlashLoan");
    uint256 constant FLASH_LOANS_DISABLED = type(uint256).max;
    uint256 public flashFeeFactor = FLASH_LOANS_DISABLED; // Fee on flash loans, as a percentage in fixed point with 18 decimals. Flash loans disabled by default by overflow from `flashFee`.

    IOracle public oracle; // Oracle for the savings rate.
    IJoin public override join; // Source of redemption funds.
    address public immutable override underlying;
    bytes6 public immutable underlyingId; // Needed to access the oracle
    uint256 public immutable override maturity;
    uint256 public chiAtMaturity = CHI_NOT_SET; // Spot price (exchange rate) between the base and an interest accruing token at maturity

    constructor(
        bytes6 underlyingId_,
        IOracle oracle_, // Underlying vs its interest-bearing version
        IJoin join_,
        uint256 maturity_,
        string memory name,
        string memory symbol
    ) ERC20Permit(name, symbol, SafeERC20Namer.tokenDecimals(address(IJoin(join_).asset()))) {
        // The join asset is this fyToken's underlying, from which we inherit the decimals
        uint256 now_ = block.timestamp;
        require(
            maturity_ > now_ && maturity_ < now_ + MAX_TIME_TO_MATURITY && maturity_ < type(uint32).max,
            "Invalid maturity"
        );

        underlyingId = underlyingId_;
        join = join_;
        maturity = maturity_;
        underlying = address(IJoin(join_).asset());
        oracle = oracle_;
    }

    modifier afterMaturity() {
        require(uint32(block.timestamp) >= maturity, "Only after maturity");
        _;
    }

    modifier beforeMaturity() {
        require(uint32(block.timestamp) < maturity, "Only before maturity");
        _;
    }

    /// @dev Point to a different Oracle or Join
    function point(bytes32 param, address value) external auth {
        if (param == "oracle") {
            require (chiAtMaturity == CHI_NOT_SET, "Already matured");
            oracle = IOracle(value);
        } else if (param == "join") {
            join = IJoin(value);
        } else revert("Unrecognized parameter");
        emit Point(param, value);
    }

    /// @dev Set the flash loan fee factor
    function setFlashFeeFactor(uint256 flashFeeFactor_) external auth {
        flashFeeFactor = flashFeeFactor_;
        emit FlashFeeFactorSet(flashFeeFactor_);
    }

    ///@dev Converts the amount of the principal to the underlying
    function convertToUnderlying(uint256 principalAmount) external override returns (uint256 underlyingAmount) {
        return _convertToUnderlying(principalAmount);
    }

    ///@dev Converts the amount of the principal to the underlying
    ///Before maturity, returns amount as if at maturity.
    function _convertToUnderlying(uint256 principalAmount) internal returns (uint256 underlyingAmount) {
        return principalAmount.wmul(_accrual());
    }

    ///@dev Converts the amount of the underlying to the principal
    function convertToPrincipal(uint256 underlyingAmount) external override returns (uint256 principalAmount) {
        return _convertToPrincipal(underlyingAmount);
    }

    ///@dev Converts the amount of the underlying to the principal
    /// Before maturity, returns amount as if at maturity.
    function _convertToPrincipal(uint256 underlyingAmount) internal returns (uint256 princpalAmount) {
        return underlyingAmount.wdivup(_accrual());
    }

    /// @dev Mature the fyToken by recording the chi.
    /// If called more than once, it will revert.
    function mature() external override afterMaturity {
        require(chiAtMaturity == CHI_NOT_SET, "Already matured");
        _mature();
    }

    /// @dev Mature the fyToken by recording the chi.
    function _mature() internal returns (uint256 _chiAtMaturity) {
        (_chiAtMaturity, ) = oracle.get(underlyingId, CHI, 0); // The value returned is an accumulator, it doesn't need an input amount
        require (_chiAtMaturity > 0, "Chi oracle malfunction"); // The chi accumulator needs to have been started
        chiAtMaturity = _chiAtMaturity;
        emit SeriesMatured(_chiAtMaturity);
    }

    /// @dev Retrieve the chi accrual since maturity, maturing if necessary.
    function accrual() external afterMaturity returns (uint256) {
        return _accrual();
    }

    /// @dev Retrieve the chi accrual since maturity, maturing if necessary. Return 1e18 if before maturity.
    function _accrual() internal returns (uint256 accrual_) {
        if (block.timestamp >= maturity) {
            if (chiAtMaturity == CHI_NOT_SET) {
                // After maturity, but chi not yet recorded. Let's record it, and accrual is then 1.
                _mature();
            } else {
                (uint256 chi, ) = oracle.get(underlyingId, CHI, 0); // The value returned is an accumulator, it doesn't need an input amount
                accrual_ = chi.wdiv(chiAtMaturity);
            }
        }
        // Return 1e18 if accrual is less than 1e18, including when accrual_ was not set.
        accrual_ = accrual_ < 1e18 ? 1e18 : accrual_;
    }

    ///@dev returns the maximum redeemable amount for the address holder in terms of the principal
    function maxRedeem(address holder) external override view returns (uint256 maxPrincipalAmount) {
        return _balanceOf[holder];
    }

    ///@dev returns the amount of underlying redeemable in terms of the principal
    function previewRedeem(uint256 principalAmount) external override beforeMaturity returns (uint256 underlyingAmount) {
        return _convertToUnderlying(principalAmount);
    }

    /// @dev Burn fyToken after maturity for an amount of principal that increases according to `chi`
    /// If `amount` is 0, the contract will redeem instead the fyToken balance of this contract. Useful for batches.
    function redeem(uint256 principalAmount, address receiver, address holder) external override afterMaturity returns (uint256 underlyingAmount) {
        principalAmount = (principalAmount == 0) ? _balanceOf[address(this)] : principalAmount;
        _burn(holder, principalAmount);
        underlyingAmount = _convertToUnderlying(principalAmount);
        join.exit(receiver, underlyingAmount.u128());

        emit Redeemed(holder, receiver, principalAmount, underlyingAmount);
    }

    /// @dev Burn fyToken after maturity for an amount of principal that increases according to `chi`
    /// If `amount` is 0, the contract will redeem instead the fyToken balance of this contract. Useful for batches.
    function redeem(address receiver, uint256 principalAmount) external override afterMaturity returns (uint256 underlyingAmount) {
        principalAmount = (principalAmount == 0) ? _balanceOf[address(this)] : principalAmount;
        _burn(msg.sender, principalAmount);
        underlyingAmount = _convertToUnderlying(principalAmount);
        join.exit(receiver, underlyingAmount.u128());

        emit Redeemed(msg.sender, receiver, principalAmount, underlyingAmount);
    }

    ///@dev returns the maximum withdrawable amount for the address holder in terms of the underlying
    function maxWithdraw(address holder) external override returns (uint256 maxUnderlyingAmount) {
        return _convertToUnderlying(_balanceOf[holder]);
    }

    ///@dev returns the amount of the principal withdrawable in terms of the underlying
    function previewWithdraw(uint256 underlyingAmount) external override beforeMaturity returns (uint256 principalAmount) {
        return _convertToPrincipal(underlyingAmount);
    }

    /// @dev Burn fyToken after maturity for an amount of underlying that increases according to `chi`
    /// If `amount` is 0, the contract will redeem instead the fyToken balance of this contract. Useful for batches.
    function withdraw(uint256 underlyingAmount, address receiver, address holder) external override afterMaturity returns (uint256 principalAmount) {
        principalAmount = (underlyingAmount == 0) ? _balanceOf[address(this)] : _convertToPrincipal(underlyingAmount);
        _burn(holder, principalAmount);
        underlyingAmount = _convertToUnderlying(principalAmount);
        join.exit(receiver, underlyingAmount.u128());

        emit Redeemed(holder, receiver, principalAmount, underlyingAmount);
    }

    /// @dev Mint fyToken providing an equal amount of underlying to the protocol
    function mintWithUnderlying(address receiver, uint256 underlyingAmount) external override beforeMaturity {
        _mint(receiver, underlyingAmount);
        join.join(msg.sender, underlyingAmount.u128());
    }

    /// @dev Mint fyTokens.
    function mint(address receiver, uint256 principalAmount) external override beforeMaturity auth {
        _mint(receiver, principalAmount);
    }

    /// @dev Burn fyTokens. The user needs to have either transferred the tokens to this contract, or have approved this contract to take them.
    function burn(address holder, uint256 principalAmount) external override auth {
        _burn(holder, principalAmount);
    }

    /// @dev Burn fyTokens.
    /// Any tokens locked in this contract will be burned first and subtracted from the amount to burn from the user's wallet.
    /// This feature allows someone to transfer fyToken to this contract to enable a `burn`, potentially saving the cost of `approve` or `permit`.
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
     * @param token The loan currency. It must be a FYDai contract.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) external view override beforeMaturity returns (uint256) {
        return token == address(this) ? type(uint256).max - _totalSupply : 0;
    }

    /**
     * @dev From ERC-3156. The fee to be charged for a given loan.
     * @param token The loan currency. It must be the asset.
     * @param principalAmount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256 principalAmount) external view override returns (uint256) {
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
     * @dev From ERC-3156. Loan `amount` fyDai to `receiver`, which needs to return them plus fee to this contract within the same transaction.
     * Note that if the initiator and the borrower are the same address, no approval is needed for this contract to take the principal + fee from the borrower.
     * If the borrower transfers the principal + fee to this contract, they will be burnt here instead of pulled from the borrower.
     * @param receiver The contract receiving the tokens, needs to implement the `onFlashLoan(address user, uint256 amount, uint256 fee, bytes calldata)` interface.
     * @param token The loan currency. Must be a fyDai contract.
     * @param principalAmount The amount of tokens lent.
     * @param data A data parameter to be passed on to the `receiver` for any custom use.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 principalAmount,
        bytes memory data
    ) external override beforeMaturity returns (bool) {
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
