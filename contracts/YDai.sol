pragma solidity ^0.5.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IPot.sol";
import "./YToken.sol";


///@dev yDai is a yToken targeting Dai
contract YDai is YToken {
    using DecimalMath for uint256;

    IVat public vat;
    IPot public pot;

    // TODO: Move to Constants.sol
    // Fixed point precisions from MakerDao
    uint8 constant public wad = 18;
    uint8 constant public ray = 27;
    uint8 constant public rad = 45;

    uint256 public maturityChi;  //maturityChi accumulator (for dsr) at maturity
    uint256 public maturityRate; //maturityRate accumulator (for stability fee) at maturity

    constructor(
        address underlying_,
        address collateral_,
        address vat_,
        address pot_,
        uint256 maturity_
    ) YToken(underlying_, collateral_, maturity_) public {
        vat = IVat(vat_);
        pot = IPot(pot_);
    }

    /// @dev Return debt in underlying of an user
    function debtOf(address user) public view returns (uint256) {
        if (isMature){
            (, uint256 rate,,,) = vat.ilks("ETH-A");
            return debt[user].muld(rate.divd(maturityRate, ray), ray);
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
        (, maturityRate,,,) = vat.ilks("ETH-A");
        maturityChi = pot.chi();
        isMature = true;
        return true;
    }
}