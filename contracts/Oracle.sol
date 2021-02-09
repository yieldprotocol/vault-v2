// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./helpers/Orchestrated.sol";


contract Oracle is Orchestrated  {

    struct OracleRead {
        uint256 spot;
        uint256 accrual;
    }

    address immutable public oracle; // Real oracle, maybe separate ones for `spot` and `rate`

    uint256 public historical; // Recorded historical prices
    
    constructor(
        address oracle_
    ) public {
        oracle = oracle_;
    }

    function spot()
        public view returns (uint256)
    {
        // return the spot price in the format we use
    }

    function rate()
        public view returns (uint256)
    {
        // return the rate acummulator in the format we use
    }

    function record(uint256 maturity)
        public
        onlyOrchestrated("Oracle: Not authorized")
    {
        if (block.timestamp >= maturity && historical[maturity] == 0) historical[maturity] = rate();
    }

    function accrual(uint256 maturity)
        public view returns(uint256)
    {
        require(historical[maturity] > 0, "Oracle: Not available");
        return rate() / historical[maturity];
    }

    function read(uint256 maturity)
        public view returns(OracleRead)
    {
        return OracleRead(spot(), accrual(maturity));   
    }
}
