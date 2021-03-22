// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/utils/contracts/token/ERC20Permit.sol";
import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "@yield-protocol/vault-interfaces/IJoin.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "./AccessControl.sol";


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
    /// @dev Safely cast an uint256 to an int128
    function i128(uint256 x) internal pure returns (int128 y) {
        require (x <= uint128(type(int128).max), "Cast overflow");
        y = int128(uint128(x));
    }

    /// @dev Safely cast an uint256 to an int128
    function u32(uint256 x) internal pure returns (uint32 y) {
        require (x <= type(uint32).max, "Cast overflow");
        y = uint32(x);
    }
}

// TODO: Setter for MAX_TIME_TO_MATURITY
contract FYToken is IFYToken, IERC3156FlashLender, AccessControl(), ERC20Permit {
    using RMath for uint256;
    using Safe256 for uint256;

    event Redeemed(address indexed from, address indexed to, uint256 amount, uint256 redeemed);

    uint256 constant internal MAX_TIME_TO_MATURITY = 126144000; // seconds in four years
    bytes32 constant internal FLASH_LOAN_RETURN = keccak256("ERC3156FlashBorrower.onFlashLoan");

    IJoin public join;                                          // Source of redemption funds.
    IOracle public oracle;                                      // Oracle for the savings rate.
    address public override asset;
    uint256 public override maturity;

    constructor(
        IOracle oracle_, // Underlying vs its interest-bearing version
        IJoin join_,
        uint256 maturity_,
        string memory name,
        string memory symbol
    ) ERC20Permit(name, symbol) {
        uint256 now_ = block.timestamp;
        require(
            maturity_ > now_ &&
            maturity_ < now_ + MAX_TIME_TO_MATURITY &&
            maturity_ < type(uint32).max,
            "Invalid maturity"
        );
        oracle = oracle_;
        join = join_;
        maturity = maturity_;
        asset = address(IJoin(join_).token());
    }

    /// @dev Mature the fyToken by recording the chi in its oracle.
    /// If called more than once, it will revert.
    /// Check if it has been called as `fyToken.oracle.recorded(fyToken.maturity())`
    function mature() 
        public override
    {
        oracle.record(maturity.u32());                                    // Cost of `record` | The oracle checks the timestamp and that it hasn't been recorded yet.        
    }

    /// @dev Burn the fyToken after maturity for an amount that increases according to `chi`
    function redeem(address to, uint256 amount)
        public override
        returns (uint256)
    {
        require(
            uint32(block.timestamp) >= maturity,
            "Not mature"
        );
        _burn(msg.sender, amount);                                  // 2 SSTORE

        uint256 redeemed = amount.rmul(oracle.accrual(maturity.u32()));   // Cost of `accrual`
        join.join(to, -(redeemed.i128()));                           // Cost of `join`
        
        emit Redeemed(msg.sender, to, amount, redeemed);
        return amount;
    }

    /// @dev Mint fyTokens.
    function mint(address to, uint256 amount)
        public override
        auth
    {
        _mint(to, amount);                                                  // 2 SSTORE
    }

    /// @dev Burn fyTokens. The user needs to have either transferred the tokens to this contract, or have approved this contract to take them. 
    function burn(address from, uint256 amount)
        public override
        auth
    {
        _burn(from, amount);
    }


    /**
     * @dev From ERC-3156. The amount of currency available to be lended.
     * @param token The loan currency. It must be a FYDai contract.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token) public view override returns (uint256) {
        return token == address(this) ? type(uint256).max - totalSupply() : 0;
    }

    /**
     * @dev From ERC-3156. The fee to be charged for a given loan.
     * @param token The loan currency. It must be a FYDai.
     * param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256) public view override returns (uint256) {
        require(token == address(this), "Unsupported currency");
        return 0;
    }

    /**
     * @dev From ERC-3156. Loan `amount` fyDai to `receiver`, which needs to return them plus fee to this contract within the same transaction.
     * Note that if the initiator and the borrower are the same address, no approval is needed for this contract to take the principal + fee from the borrower.
     * If the borrower transfers the principal + fee to this contract, they will be burnt here instead of pulled from the borrower.
     * @param receiver The contract receiving the tokens, needs to implement the `onFlashLoan(address user, uint256 amount, uint256 fee, bytes calldata)` interface.
     * @param token The loan currency. Must be a fyDai contract.
     * @param amount The amount of tokens lent.
     * @param data A data parameter to be passed on to the `receiver` for any custom use.
     */
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes memory data) public override returns(bool) {
        require(token == address(this), "Unsupported currency");
        _mint(address(receiver), amount);

        require(receiver.onFlashLoan(msg.sender, token, amount, 0, data) == FLASH_LOAN_RETURN, "Non-compliant borrower");     // Call to `onFlashLoan`

        _burn(address(receiver), amount);                                                           // 2 SSTORE
        return true;
    }

    /// @dev Burn fyTokens. 
    /// Any tokens locked in this contract will be burned first and subtracted from the amount to burn from the user's wallet.
    /// This feature allows someone to transfer fyToken to this contract to enable a `burn`, potentially saving the cost of `approve` or `permit`.
    function _burn(address from, uint256 amount)
        internal override
        returns (bool)
    {
        // First use any tokens locked in this contract
        uint256 reserve = _balanceOf[address(this)];
        uint256 remainder = amount;
        if (reserve > 0) {
            uint256 localBurn = reserve >= remainder ? remainder : reserve;
            unchecked {
                _balanceOf[address(this)] = reserve - localBurn;
                remainder -= localBurn;
            }
            emit Transfer(address(this), address(0), localBurn);
        }

        // Then pull the remainder of the burn from `src`
        if (remainder > 0) {
            _decreaseApproval(from, remainder);     // Note that if msg.sender == from this is ignored.
            require(_balanceOf[from] >= remainder, "ERC20: Insufficient balance");
            unchecked {
                _balanceOf[from] = _balanceOf[from] - remainder;
            }
            emit Transfer(from, address(0), remainder);
        }
        _totalSupply = _totalSupply - amount;
        return true;
    }
}
