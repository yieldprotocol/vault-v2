// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "erc3156/contracts/interfaces/IERC3156FlashBorrower.sol";
import "erc3156/contracts/interfaces/IERC3156FlashLender.sol";
import "@yield-protocol/utils/contracts/token/ERC20Permit.sol";
import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "@yield-protocol/vault-interfaces/IJoin.sol";
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "@yield-protocol/utils-v2/contracts/AccessControl.sol";


library FYTokenDMath { // Fixed point arithmetic in 6 decimal units
    /// @dev Multiply an amount by a fixed point factor with 6 decimals, returning an amount
    function dmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y / 1e6;
    }

    /// @dev Divide an unsigned integer by another, returning a fixed point factor with 6 decimals
    function ddiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * 1e6 / y;
    }
}

library FYTokenSafe256 {
    /// @dev Safely cast an uint256 to an uint128
    function u128(uint256 x) internal pure returns (uint128 y) {
        require (x <= type(uint128).max, "Cast overflow");
        y = uint128(x);
    }

    /// @dev Safely cast an uint256 to an int128
    function u32(uint256 x) internal pure returns (uint32 y) {
        require (x <= type(uint32).max, "Cast overflow");
        y = uint32(x);
    }
}

// TODO: Setter for MAX_TIME_TO_MATURITY
contract FYToken is IFYToken, IERC3156FlashLender, AccessControl(), ERC20Permit {
    using FYTokenDMath for uint256;
    using FYTokenSafe256 for uint256;

    event SeriesMatured(uint256 chiAtMaturity);
    event Redeemed(address indexed from, address indexed to, uint256 amount, uint256 redeemed);

    uint256 constant internal MAX_TIME_TO_MATURITY = 126144000; // seconds in four years
    bytes32 constant internal FLASH_LOAN_RETURN = keccak256("ERC3156FlashBorrower.onFlashLoan");

    IJoin public join;                                          // Source of redemption funds.
    IOracle public oracle;                                      // Oracle for the savings rate.
    bytes public constant ORACLE_DATA = abi.encode("0x0");      // Parameters to convert the raw oracle data to our format
    address public override asset;
    uint256 public override maturity;
    uint256 public chiAtMaturity = type(uint256).max;          // Spot price (exchange rate) between the base and an interest accruing token at maturity 

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
        // TODO: Check the oracle asset matches the join asset, which is the base for this fyToken
        maturity = maturity_;
        asset = address(IJoin(join_).asset());
    }

    modifier afterMaturity() {
        require(
            uint32(block.timestamp) >= maturity,
            "Only after maturity"
        );
        _;
    }

    modifier beforeMaturity() {
        require(
            uint32(block.timestamp) < maturity,
            "Only before maturity"
        );
        _;
    }

    /// @dev Mature the fyToken by recording the chi.
    /// If called more than once, it will revert.
    function mature()
        external override
        afterMaturity
    {
        require (chiAtMaturity == type(uint256).max, "Already matured");
        _mature();
    }

    /// @dev Mature the fyToken by recording the chi.
    function _mature() 
        private
        returns (uint256)
    {
        (bool success, uint256 _chiAtMaturity) = oracle.get(ORACLE_DATA);
        require (success, "No chi from oracle");
        chiAtMaturity = _chiAtMaturity;
        emit SeriesMatured(_chiAtMaturity);
        return _chiAtMaturity;
    }

    /// @dev Retrieve the chi accrual since maturity, maturing if necessary.
    function accrual()
        external
        afterMaturity
        returns (uint256)
    {
        return _accrual();
    }

    /// @dev Retrieve the chi accrual since maturity, maturing if necessary.
    /// Note: Call only after checking we are past maturity
    function _accrual()
        private
        returns (uint256)
    {
        if (chiAtMaturity == type(uint256).max) {  // After maturity, but chi not yet recorded. Let's record it, and accrual is then 1.
            _mature();
            return 1e6;
        } else {
            (bool success, uint256 chi) = oracle.get(ORACLE_DATA);
            require (success, "No chi from oracle");
            return chi.ddiv(chiAtMaturity);
        }
    }

    /// @dev Burn the fyToken after maturity for an amount that increases according to `chi`
    function redeem(address to, uint256 amount)
        external override
        afterMaturity
        returns (uint256 redeemed)
    {
        _burn(msg.sender, amount);
        redeemed = amount.dmul(_accrual());
        join.exit(to, redeemed.u128());
        
        emit Redeemed(msg.sender, to, amount, redeemed);
        return amount;
    }

    /// @dev Mint fyTokens.
    function mint(address to, uint256 amount)
        external override
        beforeMaturity
        auth
    {
        _mint(to, amount);
    }

    /// @dev Burn fyTokens. The user needs to have either transferred the tokens to this contract, or have approved this contract to take them. 
    function burn(address from, uint256 amount)
        external override
        auth
    {
        _burn(from, amount);
    }

    /**
     * @dev From ERC-3156. The amount of currency available to be lended.
     * @param token The loan currency. It must be a FYDai contract.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(address token)
        external view override
        beforeMaturity
        returns (uint256)
    {
        return token == address(this) ? type(uint256).max - totalSupply() : 0;
    }

    /**
     * @dev From ERC-3156. The fee to be charged for a given loan.
     * @param token The loan currency. It must be a FYDai.
     * param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(address token, uint256)
        external view override
        beforeMaturity
        returns (uint256)
    {
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
    function flashLoan(IERC3156FlashBorrower receiver, address token, uint256 amount, bytes memory data)
        external override
        beforeMaturity
        returns(bool)
    {
        require(token == address(this), "Unsupported currency");
        _mint(address(receiver), amount);
        require(receiver.onFlashLoan(msg.sender, token, amount, 0, data) == FLASH_LOAN_RETURN, "Non-compliant borrower");
        _burn(address(receiver), amount);
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
