pragma solidity ^0.6.2;
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "./Constants.sol";
import "./interfaces/IPot.sol";
import "./interfaces/IOracle.sol";


/// @dev ChaiOracle retrieves the price for Chai as the DSR fee from Pot
contract ChaiOracle is IOracle, Constants {
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    IPot public _pot;

    /// @dev ChaiOracle connects to Pot
    constructor (address pot_) public {
        _pot = IPot(pot_);
    }

    /// @dev We update chi and retrieve it from pot as the price
    /// Chai = Dai * price
    /// Dai = chi * Chai
    /// Chai = chi * Chai * price
    function price() public override returns(uint256) {
        uint256 chi = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        return RAY.unit().divd(chi, RAY);
    }
}