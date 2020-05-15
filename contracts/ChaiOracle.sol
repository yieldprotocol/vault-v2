pragma solidity ^0.6.2;
import "./interfaces/IPot.sol";
import "./interfaces/IOracle.sol";


/// @dev ChaiOracle retrieves the price for Chai as the DSR fee from Pot
contract ChaiOracle is IOracle{
    IPot public _pot;

    /// @dev ChaiOracle connects to Pot
    constructor (address pot_) public {
        _pot = IPot(pot_);
    }

    /// @dev We update chi and retrieve it from pot as the price
    function price() public override returns(uint256) {
        return (now > _pot.rho()) ? _pot.drip() : _pot.chi();
    }
}