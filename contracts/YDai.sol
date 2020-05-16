pragma solidity ^0.6.0;

import "@hq20/contracts/contracts/access/AuthorizedAccess.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IPot.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IYDai.sol";
import "./Constants.sol";


///@dev yDai is a yToken targeting Dai
contract YDai is AuthorizedAccess, ERC20, Constants, IYDai  {
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    event Matured(uint256 rate, uint256 chi);

    IVat internal _vat;
    IPot internal _pot; // Can we get this from Chai.sol?

    bool internal _isMature;
    uint256 internal _maturity;
    uint256 internal _chi;
    uint256 internal _rate;

    constructor(
        address vat_,
        address pot_,
        uint256 maturity_,
        string memory name,
        string memory symbol
    ) public AuthorizedAccess() ERC20(name, symbol) {
        _vat = IVat(vat_);
        _pot = IPot(pot_);
        _maturity = maturity_;
        _chi = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        (, _rate,,,) = _vat.ilks("ETH-A"); // Retrieve the MakerDAO Stability fee
        _rate = Math.max(_rate, RAY.unit()); // Floor it at 1.0
    }

    /// @dev Whether the yDai has matured or not
    function isMature() public view override returns(bool){
        return _isMature;
    }

    /// @dev Programmed time for yDai maturity
    function maturity() public view override returns(uint256){
        return _maturity;
    }

    /// @dev accumulator (for dsr) at maturity in RAY units
    //
    //  chi_now
    // ----------
    //  chi_mat
    //
    function chi() public override returns(uint256){
        uint256 chiNow = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        return chiNow.divd(_chi, RAY);
    }

    /// @dev accumulator differential for stability fee in RAY units. Returns current rate if not mature.
    //
    //  rate_now
    // ----------
    //  rate_mat
    //
    function rate() public view override returns(uint256){
        (, uint256 rateNow,,,) = _vat.ilks("ETH-A");
        return rateNow.divd(_rate, RAY);
    }

    /// @dev Mature yDai and capture maturity data
    function mature() public override {
        require(
            // solium-disable-next-line security/no-block-members
            now > _maturity,
            "YDai: Too early to mature"
        );
        (, _rate,,,) = _vat.ilks("ETH-A"); // Retrieve the MakerDAO Vat
        _rate = Math.max(_rate, RAY.unit()); // Floor it at 1.0
        _chi = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        _isMature = true;
        emit Matured(_rate, _chi);
    }

    /// @dev Mint yDai. Only callable by Mint contracts.
    function mint(address to, uint256 yDai) public override onlyAuthorized("YDai: Not Authorized") {
        _mint(to, yDai);
    }

    /// @dev Burn yDai. Only callable by Mint contracts.
    function burn(address from, uint256 yDai) public override onlyAuthorized("YDai: Not Authorized") {
        _burn(from, yDai);
    }
}