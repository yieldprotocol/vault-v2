// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/src/token/ERC20Permit.sol";
import "@yield-protocol/utils-v2/src/token/SafeERC20Namer.sol";
import "@yield-protocol/utils-v2/src/access/AccessControl.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "../interfaces/IJoin.sol";
import "../interfaces/IOracle.sol";
import "../constants/Constants.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";

contract VYToken is UUPSUpgradeable, AccessControl, ERC20Permit, Constants {
    using Math for uint256;
    using Cast for uint256;

    event Redeemed(address indexed holder, address indexed receiver, uint256 principalAmount, uint256 underlyingAmount);

    bool public initialized;

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
        _revokeRole(ROOT, msg.sender); // Remove the deployer's ROOT role
    }

    /// @dev Give the ROOT role and create a LOCK role with itself as the admin role and no members. 
    /// Calling setRoleAdmin(msg.sig, LOCK) means no one can grant that msg.sig role anymore.
    function initialize (address root_, string memory name_, string memory symbol_, uint8 decimals_) public {
        require(!initialized, "Already initialized");
        initialized = true;             // On an uninitialized contract, no governance functions can be executed, because no one has permission to do so
        _grantRole(ROOT, root_);      // Grant ROOT
        _setRoleAdmin(LOCK, LOCK);      // Create the LOCK role by setting itself as its own admin, creating an independent role tree
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
    }

    /// @dev Allow to set a new implementation
    function _authorizeUpgrade(address newImplementation) internal override auth {}

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
}