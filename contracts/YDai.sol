pragma solidity ^0.6.0;

import "@hq20/contracts/contracts/access/AuthorizedAccess.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IPot.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IYDai.sol";
import "./Constants.sol";
import "./UserProxy.sol";


///@dev yDai is a yToken targeting Dai
contract YDai is AuthorizedAccess(), UserProxy(), ERC20, Constants, IYDai  {
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    event Matured(uint256 rate, uint256 chi);

    IVat internal _vat;
    IPot internal _pot;
    ITreasury internal _treasury;

    bool internal _isMature;
    uint256 internal _maturity;
    uint256 internal _chi;      // Chi at maturity
    uint256 internal _rate;     // Rate at maturity

    constructor(
        address vat_,
        address pot_,
        address treasury_,
        uint256 maturity_,
        string memory name,
        string memory symbol
    ) public ERC20(name, symbol) {
        _vat = IVat(vat_);
        _pot = IPot(pot_);
        _treasury = ITreasury(treasury_);
        _maturity = maturity_;
        _chi = RAY.unit();
        _rate = RAY.unit();
    }

    /// @dev Whether the yDai has matured or not
    function isMature() public view override returns(bool){
        return _isMature;
    }

    /// @dev Programmed time for yDai maturity
    function maturity() public view override returns(uint256){
        return _maturity;
    }

    /// @dev Chi differential between maturity and now in RAY. Returns 1.0 if not mature.
    //
    //          chi_now
    // chi() = ---------
    //          chi_mat
    //
    function chi() public override returns(uint256){
        if (!isMature()) return _chi;
        uint256 chiNow = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        return chiNow.divd(_chi, RAY);
    }

    /// @dev Rate differential between maturity and now in RAY. Returns 1.0 if not mature.
    //
    //           rate_now
    // rate() = ----------
    //           rate_mat
    //
    function rate() public view override returns(uint256){
        if (!isMature()) return _rate;
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
        require(
            !isMature(),
            "YDai: Already matured"
        );
        (, _rate,,,) = _vat.ilks("ETH-A"); // Retrieve the MakerDAO Vat
        _rate = Math.max(_rate, RAY.unit()); // Floor it at 1.0
        _chi = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        _isMature = true;
        emit Matured(_rate, _chi);
    }

    /// @dev Burn yTokens and return their dai equivalent value, pulled from the Treasury
    // user --- yDai ---> us
    // us   --- Dai  ---> user
    function redeem(address user, uint256 yDaiAmount)
        public onlyHolderOrProxy(user, "YDai: Only Holder Or Proxy") {
        require(
            isMature(),
            "YDai: yDai is not mature"
        );
        _burn(user, yDaiAmount);                         // Burn yDai from user
        uint256 daiAmount = yDaiAmount.muld(chi(), RAY); // User gets interest for holding after maturity
        _treasury.pullDai(user, daiAmount);              // Give dai to user, from Treasury
    }

    /// @dev Mint yDai. Only callable by Dealer contracts.
    function mint(address to, uint256 yDaiAmount) public override onlyAuthorized("YDai: Not Authorized")
        {
        _mint(to, yDaiAmount);
    }

    /// @dev Burn yDai. Only callable by Dealer contracts.
    function burn(address from, uint256 yDaiAmount) public override onlyAuthorized("YDai: Not Authorized") {
        _burn(from, yDaiAmount);
    }
}