// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./interfaces/IOracle.sol";
// import "@yield-protocol/utils/contracts/access/Orchestrated.sol";
import "@yield-protocol/utils/contracts/token/ERC20Permit.sol";
import "@yield-protocol/utils/contracts/token/IERC20.sol";


contract FYToken is /* Orchestrated(),*/ ERC20Permit  {

    event Redeemed(address indexed from, address indexed to, uint256 amount);

    uint256 constant internal MAX_TIME_TO_MATURITY = 126144000; // seconds in four years

    IERC20 public base;
    IOracle public oracle;
    uint256 public maturity;

    constructor(
        IERC20 base_,
        IOracle oracle_, // Underlying vs its interest-bearing version
        uint256 maturity_,
        string memory name,
        string memory symbol
    ) ERC20Permit(name, symbol) {
        // require(maturity_ > block.timestamp && maturity_ < block.timestamp + MAX_TIME_TO_MATURITY, "FYToken: Invalid maturity");
        base = base_;
        oracle = oracle_;
        maturity = maturity_;
    }

    /*
    function mature() 
        public
    {
        oracle.record(maturity); // The oracle checks the timestamp and that it hasn't been recorded yet.        
    }

    function redeem(uint256 amount)
        public
        returns (uint256)
    {
        require(
            block.timestamp >= maturity,
            "FYToken: fyToken is not mature"
        );
        _burn(from, amount);

        // consider moving these two lines to Vat. Credit the user's account with the redemption value, then they can remove via the join.
        uint256 redeemed = amount * oracle.accrual(maturity);
        treasury.pull(base, to, amount);
        
        emit Redeemed(from, to, amount);
        return amount;
    } */

    /// @dev Mint fyToken.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param to Wallet to mint the fyToken in.
    /// @param amount Amount of fyToken to mint.
    function mint(address to, uint256 amount)
        public
        /* auth */
    {
        _mint(to, amount);
    }

    /// @dev Burn fyToken.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param from Wallet to burn the fyToken from.
    /// @param amount Amount of fyToken to burn.
    function burn(address from, uint256 amount)
        public
        /* auth */
    {
        _burn(from, amount);
    }
}
