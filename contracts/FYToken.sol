// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/ITreasury.sol";
import "./interfaces/IOracle.sol";
import "./helpers/Orchestrated.sol";


contract FYToken is Orchestrated()  {

    event Redeemed(address indexed from, address indexed to, uint256 amount);

    uint256 constant internal MAX_TIME_TO_MATURITY = 126144000; // seconds in four years

    IOracle public oracle;
    ITreasury public treasury;
    uint256 public maturity;

    constructor(
        ITreasury treasury_,
        IOracle oracle_, // Underlying vs its interest-bearing version
        uint256 maturity_,
        string memory name,
        string memory symbol
    ) public {
        require(maturity_ > block.timestamp && maturity_ < block.timestamp + MAX_TIME_TO_MATURITY, "FYToken: Invalid maturity");
        treasury = treasury_;
        oracle = oracle_;
        maturity = maturity_;
    }

    function mature() {
        oracle.record(maturity); // The oracle checks the timestamp and that it hasn't been recorded yet.        
    }

    // Redeem can only be called by `Vat` which needs to check all the collaterals in the respective vault and work out the redeemed amount from the accruals.
    function redeem(uint256 amount)
        public
        returns (uint256)
    {
        require(
            block.timestamp >= maturity,
            "FYToken: fyToken is not mature"
        );
        int256 _accrual = oracle.accrual(maturity);
        uint256 redeemed = _accrual > 0 ? amount * _accrual : amount; // If accrual is positive the collateral used accrued value, which we honour. If the accrual is negative we ignore it.
        _burn(from, amount);
        treasury.pull(to, amount);
        emit Redeemed(from, to, amount);
        return amount;
    }

    /// @dev Mint fyToken. Only callable by Controller contracts.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param to Wallet to mint the fyToken in.
    /// @param fyTokenAmount Amount of fyToken to mint.
    function mint(address to, uint256 fyTokenAmount) public override onlyOrchestrated("FYToken: Not Authorized") {
        _mint(to, fyTokenAmount);
    }

    /// @dev Burn fyToken. Only callable by Controller contracts.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param from Wallet to burn the fyToken from.
    /// @param fyTokenAmount Amount of fyToken to burn.
    function burn(address from, uint256 fyTokenAmount) public override onlyOrchestrated("FYToken: Not Authorized") {
        _burn(from, fyTokenAmount);
    }
}
