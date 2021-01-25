// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/IOracle.sol";
import "./helpers/Orchestrated.sol";


contract Oracle is IOracle is Orchestrated  {

    Contract public immutable oracle; // Real oracle

    uint256 public override historical; // Recorded historical prices
    
    /// @dev The constructor:
    /// Sets the name and symbol for the fyDai token.
    /// Sets the maturity date for the fyDai, in unix time.
    constructor(
        Contract oracle_
    ) public {
        oracle = oracle_;
    }

    function rate()
        public returns (uint256)
    {
        // return the rate in the format we use
    }

    function record(uint256 maturity)
        public
        onlyOrchestrated("Oracle: Not Authorized")
    {
        if (block.timestamp >= maturity && historical[maturity] == 0) historical[maturity] = rate();
    }

    function rateChange(uint256 maturity)
        public returns(uint256)
    {
        require(historical[maturity] > 0, "Oracle: Not available");
        return divd(rate(), historical[maturity]);
    }
}
