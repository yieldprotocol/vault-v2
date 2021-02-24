// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./interfaces/IOracle.sol";
import "./interfaces/IJoin.sol";
// import "@yield-protocol/utils/contracts/access/Orchestrated.sol";
import "@yield-protocol/utils/contracts/token/ERC20Permit.sol";


contract FYToken is /* Orchestrated(),*/ ERC20Permit  {

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
        require(maturity_ > block.timestamp && maturity_ < block.timestamp + MAX_TIME_TO_MATURITY, "Invalid maturity");
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
        oracle.record(maturity); // The oracle checks the timestamp and that it hasn't been recorded yet.        
    }

    /// @dev Burn the fyToken after maturity for an amount that increases according to `chi`
    function redeem(address to, uint256 amount)
        public
        returns (uint256)
    {
        require(
            block.timestamp >= maturity,
            "fyToken is not mature"
        );
        _burn(msg.sender, amount);

        // Consider moving these two lines to Ladle.
        uint256 redeemed = amount * oracle.accrual(maturity);
        join.join(to, -int128(uint128(redeemed))); // TODO: SafeCast
        
        emit Redeemed(msg.sender, to, amount, redeemed);
        return amount;
    }

    /// @dev Mint fyTokens.
    function mint(address to, uint256 amount)
        public
        /* auth */
    {
        _mint(to, amount);
    }

    /// @dev Burn fyTokens.
    function burn(address from, uint256 amount)
        public
        /* auth */
    {
        _burn(from, amount);
    }
}
