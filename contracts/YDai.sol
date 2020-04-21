pragma solidity ^0.5.2;

import "./YToken.sol";

///@dev yDai is a yToken targeting Dai


contract YDai is YToken {
    address public vat;
    address public pot;
    uint256 public chi;  //chi accumulator at maturity
    uint256 public rate; //rate accumulator at maturity

    constructor(
        address underlying_,
        address collateral_,
        address vat_,
        address pot_,
        uint256 maturity_
    ) YToken(underlying_, collateral_, maturity_) public {
        vat = vat_;
        pot = pot_;
    }
}