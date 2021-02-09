// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;


contract Oracle {
    address immutable public oracle; // Real oracle
    uint256 public historical; // Recorded historical values
    
    constructor(address oracle_) public {
        oracle = oracle_;
    }

    function spot()
        public view returns (uint256)
    {
        // return the spot price or accumulator in the format we use
    }

    function record(uint256 timestamp)
        public
        returns (uint256)
    {
        require (block.timestamp >= timestamp, "Oracle: Too early");
        require (historical[timestamp] == 0, "Oracle: Already recorded");
        uint256 _spot = spot();
        historical[timestamp] = _spot;
        emit Recorded(timestamp, _spot);
        return _spot;
    }

    function accrual(uint256 timestamp)
        public view returns(uint256)
    {
        require(historical[timestamp] > 0, "Oracle: Not available");
        return value() / historical[timestamp];
    }
}
