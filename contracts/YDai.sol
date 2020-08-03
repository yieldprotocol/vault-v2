// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/Math.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IPot.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IYDai.sol";
import "./interfaces/IFlashMinter.sol";
import "./helpers/Delegable.sol";
import "./helpers/DecimalMath.sol";
import "./helpers/Orchestrated.sol";
import "./helpers/ERC20Permit.sol";



/**
 * @dev yDai is a yToken targeting Chai.
 * Each yDai contract has a specific maturity time. One yDai is worth one Chai at or after maturity time.
 * At maturity, the yDai can be triggered to mature, which records the current rate and chi from MakerDAO and enables redemption.
 * Redeeming an yDai means burning it, and the contract will retrieve Dai from Treasury equal to one Dai times the growth in chi since maturity.
 * yDai also tracks the MakerDAO stability fee accumulator at the time of maturity, and the growth since. This is not used internally.
 * Minting and burning of yDai is restricted to orchestrated contracts. Redeeming and flash-minting is allowed to anyone.
 */

contract YDai is Orchestrated(), Delegable(), DecimalMath, ERC20Permit, IYDai  {

    event Redeemed(address indexed from, address indexed to, uint256 yDaiIn, uint256 daiOut);
    event Matured(uint256 rate, uint256 chi);

    bytes32 public constant WETH = "ETH-A";

    IVat internal _vat;
    IPot internal _pot;
    ITreasury internal _treasury;

    bool public override isMature;
    uint256 public override maturity;
    uint256 public override chi0;      // Chi at maturity
    uint256 public override rate0;     // Rate at maturity

    /// @dev The constructor:
    /// Sets the name and symbol for the yDai token.
    /// Connects to Vat, Jug, Pot and Treasury.
    /// Sets the maturity date for the yDai, in unix time.
    /// Initializes chi and rate at maturity time as 1.0 with 27 decimals.
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
    function chiGrowth() public view override returns(uint256){
        if (isMature != true) return chi0;
        return Math.min(rateGrowth(), divd(_pot.chi(), chi0)); // Rounding in favour of the protocol
    }

    /// @dev Rate differential between maturity and now in RAY. Returns 1.0 if not mature.
    /// rateGrowth is floored to 1.0.
    //
    //                 rate_now
    // rateGrowth() = ----------
    //                 rate_mat
    //
    function rateGrowth() public view override returns(uint256){
        if (isMature != true) return rate0;
        (, uint256 rate,,,) = _vat.ilks(WETH);
        return Math.max(UNIT, divdrup(rate, rate0)); // Rounding in favour of the protocol
    }

    /// @dev Mature yDai and capture chi and rate
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
        chi0 = _pot.chi();
        isMature = true;
        emit Matured(rate0, chi0);
    }

    /// @dev Burn yTokens and return their dai equivalent value, pulled from the Treasury
    /// During unwind, `_treasury.pullDai()` will revert which is right.
    /// `from` needs to tell yDai to approve the burning of the yDai tokens.
    /// `from` can delegate to other addresses to redeem his yDai and put the Dai proceeds in the `to` wallet.
    /// The collateral needed changes according to series maturity and MakerDAO rate and chi, depending on collateral type.
    /// @param from Wallet to burn yDai from.
    /// @param to Wallet to put the Dai in.
    /// @param yDaiAmount Amount of yDai to burn.
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
    /// @param to Wallet to mint the yDai in.
    /// @param yDaiAmount Amount of yDai to mint.
    /// @param data User-defined data to pass on to `executeOnFlashMint()`
    function flashMint(address to, uint256 yDaiAmount, bytes calldata data) external override {
        _mint(to, yDaiAmount);
        IFlashMinter(msg.sender).executeOnFlashMint(to, yDaiAmount, data);
        _burn(to, yDaiAmount);
    }

    /// @dev Mint yDai. Only callable by Controller contracts.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param to Wallet to mint the yDai in.
    /// @param yDaiAmount Amount of yDai to mint.
    function mint(address to, uint256 yDaiAmount) public override onlyOrchestrated("YDai: Not Authorized") {
        _mint(to, yDaiAmount);
    }

    /// @dev Burn yDai. Only callable by Controller contracts.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param from Wallet to burn the yDai from.
    /// @param yDaiAmount Amount of yDai to burn.
    function burn(address from, uint256 yDaiAmount) public override onlyOrchestrated("YDai: Not Authorized") {
        _burn(from, yDaiAmount);
    }

    /// @dev Creates `yDaiAmount` tokens and assigns them to `to`, increasing the total supply, up to a limit of 2**112.
    /// @param to Wallet to mint the yDai in.
    /// @param yDaiAmount Amount of yDai to mint.
    function _mint(address to, uint256 yDaiAmount) internal override {
        super._mint(to, yDaiAmount);
        require(totalSupply() <= 5192296858534827628530496329220096, "YDai: Total supply limit exceeded"); // 2**112
    }
}
