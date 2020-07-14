pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IJug.sol";
import "./interfaces/IPot.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IYDai.sol";
import "./interfaces/IFlashMinter.sol";
import "./helpers/Delegable.sol";
import "./helpers/DecimalMath.sol";
import "./helpers/Orchestrated.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev yDai is a yToken targeting Dai.
contract YDai is Orchestrated(), Delegable(), DecimalMath, ERC20, IYDai  {

    event Redeemed(address indexed from, address indexed to, uint256 yDaiIn, uint256 daiOut);
    event Matured(uint256 rate, uint256 chi);

    bytes32 public constant WETH = "ETH-A";

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
        chi0 = UNIT;
        rate0 = UNIT;
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
        return Math.min(rateGrowth(), divd(chiNow, chi0));
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
        (, uint256 rho) = _jug.ilks(WETH);
        if (now > rho) {
            rateNow = _jug.drip(WETH);
            // console.log(rateNow);
        } else {
            (, rateNow,,,) = _vat.ilks(WETH);
        }
        return divd(rateNow, rate0);
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
        (, rate0,,,) = _vat.ilks(WETH); // Retrieve the MakerDAO Vat
        rate0 = Math.max(rate0, UNIT); // Floor it at 1.0
        chi0 = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        isMature = true;
        emit Matured(rate0, chi0);
    }

    /// @dev Burn yTokens and return their dai equivalent value, pulled from the Treasury
    // TODO: Consider whether to allow this to be gracefully unwind, instead of letting `_treasury.pullDai()` revert.
    // from --- yDai ---> us
    // us   --- Dai  ---> to
    function redeem(address from, address to, uint256 yDaiAmount)
        public onlyHolderOrDelegate(from, "YDai: Only Holder Or Delegate") {
        require(
            isMature == true,
            "YDai: yDai is not mature"
        );
        _burn(from, yDaiAmount);                              // Burn yDai from `from`
        uint256 daiAmount = muld(yDaiAmount, chiGrowth());    // User gets interest for holding after maturity
        _treasury.pullDai(to, daiAmount);                     // Give dai to `to`, from Treasury
        emit Redeemed(from, to, yDaiAmount, daiAmount);
    }

    /// @dev Flash-mint yDai. Calls back on `IFlashMinter.executeOnFlashMint()`
    function flashMint(address to, uint256 yDaiAmount, bytes calldata data) external override {
        _mint(to, yDaiAmount);
        IFlashMinter(msg.sender).executeOnFlashMint(to, yDaiAmount, data);
        _burn(to, yDaiAmount);
    }

    /// @dev Mint yDai. Only callable by Controller contracts.
    function mint(address to, uint256 yDaiAmount) public override onlyOrchestrated("YDai: Not Authorized")
        {
        _mint(to, yDaiAmount);
    }

    /// @dev Burn yDai. Only callable by Controller contracts.
    function burn(address from, uint256 yDaiAmount) public override onlyOrchestrated("YDai: Not Authorized") {
        _burn(from, yDaiAmount);
    }
}