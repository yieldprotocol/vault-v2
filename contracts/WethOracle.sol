pragma solidity ^0.6.2;
import "./interfaces/IVat.sol";
import "./interfaces/IOracle.sol";


/// @dev WethOracle returns the price of Weth as retrieved from MakerDAO
contract WethOracle is IOracle {
    IVat public _vat;

    /// @dev To calculate price we retrieve rate and spot from Vat
    constructor (address vat_) public {
        _vat = IVat(vat_);
    }

    /// @dev Price is the spot for that given collateral in MakerDAO
    /// weth = dai * price
    function price() public override returns(uint256) {
        (,, uint256 spot,,) = _vat.ilks("ETH-A");  // Stability fee and collateralization ratio for Weth
        return spot;
    }
}