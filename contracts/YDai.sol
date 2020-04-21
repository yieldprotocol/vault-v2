pragma solidity ^0.5.2;

import "./YToken.sol";


contract YDai is YToken {
    address public vat;
    address public pot;
    uint256 public chi;  //chi accumulator at maturity
    uint256 public rate; //rate accumulator at maturity

    constructor(
        address underlying_,
        address collateral_,
        uint256 maturity_,
        address vat_,
        address pot_
    ) YToken(underlying_, collateral_, maturity_) public {
        vat = vat_;
        pot = pot_;
    }
}