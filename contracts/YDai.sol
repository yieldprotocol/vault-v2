pragma solidity ^0.5.2;

import "./YToken.sol";
import "./IVat.sol";
import "./IPot.sol";

///@dev yDai is a yToken targeting Dai


contract YDai is YToken {
    Vat public vat;
    Pot public pot; 

    uint256 public chi;  //chi accumulator at maturity
    uint256 public rate; //rate accumulator at maturity

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