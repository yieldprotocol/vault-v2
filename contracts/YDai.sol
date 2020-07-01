pragma solidity ^0.6.0;

import "@hq20/contracts/contracts/access/AuthorizedAccess.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IJug.sol";
import "./interfaces/IPot.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IYDai.sol";
import "./interfaces/IFlashMinter.sol";
import "./Constants.sol";
import "./UserProxy.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev yDai is a yToken targeting Dai.
contract YDai is AuthorizedAccess(), UserProxy(), ERC20, Constants, IYDai  {
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    event Matured(uint256 rate, uint256 chi);

    IVat internal _vat;
    IJug internal _jug;
    IPot internal _pot;
    ITreasury internal _treasury;

    bool public override isMature;
    uint256 public override maturity;
    uint256 public override chi0;      // Chi at maturity
    uint256 public override rate0;     // Rate at maturity

    constructor(
        address vat_,
        address jug_,
        address pot_,
        address treasury_,
        uint256 maturity_,
        string memory name,
        string memory symbol
    ) public ERC20(name, symbol) {
        _vat = IVat(vat_);
        _jug = IJug(jug_);
        _pot = IPot(pot_);
        _treasury = ITreasury(treasury_);
        maturity = maturity_;
        chi0 = RAY.unit();
        rate0 = RAY.unit();
    }

    /// @dev Chi differential between maturity and now in RAY. Returns 1.0 if not mature.
    /// If rateGrowth < chiGrowth, returns rate.
    //
    //          chi_now
    // chi() = ---------
    //          chi_mat
    //
    function chiGrowth() public override returns(uint256){
        if (isMature != true) return chi0;
        uint256 chiNow = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        return Math.min(rateGrowth(), chiNow.divd(chi0, RAY));
    }

    /// @dev Rate differential between maturity and now in RAY. Returns 1.0 if not mature.
    //
    //           rate_now
    // rateGrowth() = ----------
    //           rate_mat
    //
    function rateGrowth() public override returns(uint256){
        if (isMature != true) return rate0;
        uint256 rateNow;
        (, uint256 rho) = _jug.ilks("ETH-A"); // "WETH" for weth.sol, "ETH-A" for MakerDAO
        if (now > rho) {
            rateNow = _jug.drip("ETH-A");
            // console.log(rateNow);
        } else {
            (, rateNow,,,) = _vat.ilks("ETH-A");
        }
        return rateNow.divd(rate0, RAY);
    }

    /// @dev Mature yDai and capture maturity data
    function mature() public override {
        require(
            // solium-disable-next-line security/no-block-members
            now > maturity,
            "YDai: Too early to mature"
        );
        require(
            isMature != true,
            "YDai: Already matured"
        );
        (, rate0,,,) = _vat.ilks("ETH-A"); // Retrieve the MakerDAO Vat
        rate0 = Math.max(rate0, RAY.unit()); // Floor it at 1.0
        chi0 = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        isMature = true;
        emit Matured(rate0, chi0);
    }

    /// @dev Burn yTokens and return their dai equivalent value, pulled from the Treasury
    // TODO: Consider whether to allow this to be gracefully unwind, instead of letting `_treasury.pullDai()` revert.
    // user --- yDai ---> us
    // us   --- Dai  ---> user
    function redeem(address user, uint256 yDaiAmount)
        public onlyHolderOrProxy(user, "YDai: Only Holder Or Proxy") {
        require(
            isMature == true,
            "YDai: yDai is not mature"
        );
        _burn(user, yDaiAmount);                              // Burn yDai from user
        uint256 daiAmount = yDaiAmount.muld(chiGrowth(), RAY); // User gets interest for holding after maturity
        _treasury.pullDai(user, daiAmount);                   // Give dai to user, from Treasury
    }

    /// @dev Flash-mint yDai. Calls back on `IFlashMinter.executeOnFlashMint()`
    function flashMint(address to, uint256 yDaiAmount) public {
        _mint(to, yDaiAmount);
        IFlashMinter(msg.sender).executeOnFlashMint();
        _burn(to, yDaiAmount);
    }

    /// @dev Mint yDai. Only callable by Dealer contracts.
    function mint(address to, uint256 yDaiAmount) public override onlyAuthorized("YDai: Not Authorized") {
        _mint(to, yDaiAmount);
    }

    /// @dev Burn yDai. Only callable by Dealer contracts.
    function burn(address from, uint256 yDaiAmount) public override onlyAuthorized("YDai: Not Authorized") {
        _burn(from, yDaiAmount);
    }
}