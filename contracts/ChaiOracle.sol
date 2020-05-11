pragma solidity ^0.6.2;
import "./interfaces/IPot.sol";
import "./interfaces/IOracle.sol";


contract ChaiOracle is IOracle{
    IPot _pot;

    constructor (address pot_) public {
        _pot = IPot(pot_);
    }

    function price() public override returns(uint256) {
        return (now > _pot.rho()) ? _pot.drip() : _pot.chi();
    }
}