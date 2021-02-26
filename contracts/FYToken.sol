// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./interfaces/IOracle.sol";
import "./interfaces/IJoin.sol";
// import "@yield-protocol/utils/contracts/access/Orchestrated.sol";
import "@yield-protocol/utils/contracts/token/ERC20Permit.sol";


library RMath { // Fixed point arithmetic in Ray units
    /// @dev Multiply an amount by a fixed point factor in ray units, returning an amount
    function rmul(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            uint256 _z = uint256(x) * uint256(y) / 1e27;
            require (_z <= type(uint128).max, "RMUL Overflow");
            z = uint128(_z);
        }
    }
}

library Safe128 {
    /// @dev Safely cast an uint128 to an int128
    function i128(uint128 x) internal pure returns (int128 y) {
        require (x <= uint128(type(int128).max), "Cast overflow");
        y = int128(x);
    }
}

// TODO: Setter for MAX_TIME_TO_MATURITY
// TODO: Instantiating fyToken with maturity in the past
contract FYToken is /* Orchestrated(),*/ ERC20Permit  {
    using RMath for uint128;
    using Safe128 for uint128;

    event Redeemed(address indexed from, address indexed to, uint256 amount, uint256 redeemed);

    uint256 constant internal MAX_TIME_TO_MATURITY = 126144000; // seconds in four years

    IOracle public oracle;                                      // Oracle for the savings rate.
    IJoin public join;                                          // Source of redemption funds.
    uint32 public maturity;

    constructor(
        IOracle oracle_, // Underlying vs its interest-bearing version
        IJoin join_,
        uint32 maturity_,
        string memory name,
        string memory symbol
    ) ERC20Permit(name, symbol) {
        uint32 now_ = uint32(block.timestamp);
        require(maturity_ > now_ && maturity_ < now_ + MAX_TIME_TO_MATURITY, "Invalid maturity");
        oracle = oracle_;
        join = join_;
        maturity = maturity_;
    }

    /// @dev Mature the fyToken by recording the chi in its oracle.
    /// If called more than once, it will revert.
    /// Check if it has been called as `fyToken.oracle.recorded(fyToken.maturity())`
    function mature() 
        public
    {
        oracle.record(maturity);                                    // Cost of `record` | The oracle checks the timestamp and that it hasn't been recorded yet.        
    }

    /// @dev Burn the fyToken after maturity for an amount that increases according to `chi`
    function redeem(address to, uint128 amount)
        public
        returns (uint128)
    {
        require(
            uint32(block.timestamp) >= maturity,
            "Not mature"
        );
        _burn(msg.sender, amount);                                  // 2 SSTORE

        // Consider moving these two lines to Ladle.
        uint128 redeemed = amount.rmul(oracle.accrual(maturity));   // Cost of `accrual`
        join.join(to, -(redeemed.i128()));                           // Cost of `join`
        
        emit Redeemed(msg.sender, to, amount, redeemed);
        return amount;
    }

    /// @dev Mint fyTokens.
    function mint(address to, uint256 amount)
        public
        /* auth */
    {
        _mint(to, amount);                                        // 2 SSTORE
    }

    /// @dev Burn fyTokens.
    function burn(address from, uint256 amount)
        public
        /* auth */
    {
        _burn(from, amount);                                        // 2 SSTORE
    }
}
