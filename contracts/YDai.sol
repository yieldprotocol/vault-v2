pragma solidity ^0.5.2;

import "./YToken.sol";
import "./IVat.sol";
import "./IPot.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";


///@dev yDai is a yToken targeting Dai
contract YDai is YToken {
    using DecimalMath for uint256;

    Vat public vat;
    Pot public pot;

    uint256 public chi;  //chi accumulator (for dsr) at maturity
    uint256 public rate; //rate accumulator (for stability fee) at maturity

    constructor(
        address underlying_,
        address collateral_,
        address vat_,
        address pot_,
        uint256 maturity_
    ) YToken(underlying_, collateral_, maturity_) public {
        vat = Vat(vat_);
        pot = Pot(pot_);
    }

    /// @dev Return debt in underlying of an user
    function debtOf(address user) public view returns (uint256) {
        if (isMature){
            uint256 currentRate;
            (, currentRate,,,) = vat.ilks("ETH-A");
            return debt[user].muld(currentRate.divd(rate, 27) ,27);
        } else {
            return debt[user];
        }
    }

    /// @dev Mature yToken to make redeemable.
    function mature() public returns (bool) {
        require(
            // solium-disable-next-line security/no-block-members
            now > maturity,
            "YToken: Too early to mature"
        );
        (, rate,,,) = vat.ilks("ETH-A");
        chi = pot.chi();
        isMature = true;
        return true;
    }
}