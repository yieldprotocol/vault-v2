// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.6.10;

import "@openzeppelin/contracts/math/Math.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IPot.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IEDai.sol";
import "./interfaces/IFlashMinter.sol";
import "./helpers/Delegable.sol";
import "./helpers/DecimalMath.sol";
import "./helpers/Orchestrated.sol";
import "./helpers/ERC20Permit.sol";



/**
 * @dev eDai is aeToken targeting Chai.
 * Each eDai contract has a specific maturity time. One eDai is worth one Chai at or after maturity time.
 * At maturity, the eDai can be triggered to mature, which records the current rate and chi from MakerDAO and enables redemption.
 * Redeeming an eDai means burning it, and the contract will retrieve Dai from Treasury equal to one Dai times the growth in chi since maturity.
 * eDai also tracks the MakerDAO stability fee accumulator at the time of maturity, and the growth since. This is not used internally.
 * Minting and burning of eDai is restricted to orchestrated contracts. Redeeming and flash-minting is allowed to anyone.
 */

contract EDai is IEDai, Orchestrated(), Delegable(), DecimalMath, ERC20Permit  {

    event Redeemed(address indexed from, address indexed to, uint256 eDaiIn, uint256 daiOut);
    event Matured(uint256 rate, uint256 chi);

    bytes32 public constant WETH = "ETH-A";

    uint256 constant internal MAX_TIME_TO_MATURITY = 126144000; // seconds in four years

    IVat public vat;
    IPot public pot;
    ITreasury public treasury;

    bool public override isMature;
    uint256 public override maturity;
    uint256 public override chi0;      // Chi at maturity
    uint256 public override rate0;     // Rate at maturity

    uint public override unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'EDai: Locked');
        unlocked = 0;
        _;
        unlocked = 1;
    }
    
    /// @dev The constructor:
    /// Sets the name and symbol for the eDai token.
    /// Connects to Vat, Jug, Pot and Treasury.
    /// Sets the maturity date for the eDai, in unix time.
    /// Initializes chi and rate at maturity time as 1.0 with 27 decimals.
    constructor(
        address treasury_,
        uint256 maturity_,
        string memory name,
        string memory symbol
    ) public ERC20Permit(name, symbol) {
        // solium-disable-next-line security/no-block-members
        require(maturity_ > now && maturity_ < now + MAX_TIME_TO_MATURITY, "EDai: Invalid maturity");
        treasury = ITreasury(treasury_);
        vat = treasury.vat();
        pot = treasury.pot();
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
        return Math.min(rateGrowth(), divd(pot.chi(), chi0)); // Rounding in favour of the protocol
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
        (, uint256 rate,,,) = vat.ilks(WETH);
        return Math.max(UNIT, divdrup(rate, rate0)); // Rounding in favour of the protocol
    }

    /// @dev Mature eDai and capture chi and rate
    function mature() public override {
        require(
            // solium-disable-next-line security/no-block-members
            now > maturity,
            "EDai: Too early to mature"
        );
        require(
            isMature != true,
            "EDai: Already matured"
        );
        (, rate0,,,) = vat.ilks(WETH); // Retrieve the MakerDAO Vat
        rate0 = Math.max(rate0, UNIT); // Floor it at 1.0
        chi0 = pot.chi();
        isMature = true;
        emit Matured(rate0, chi0);
    }

    /// @dev BurneTokens and return their dai equivalent value, pulled from the Treasury
    /// During unwind, `treasury.pullDai()` will revert which is right.
    /// `from` needs to tell eDai to approve the burning of the eDai tokens.
    /// `from` can delegate to other addresses to redeem his eDai and put the Dai proceeds in the `to` wallet.
    /// The collateral needed changes according to series maturity and MakerDAO rate and chi, depending on collateral type.
    /// @param from Wallet to burn eDai from.
    /// @param to Wallet to put the Dai in.
    /// @param eDaiAmount Amount of eDai to burn.
    // from --- eDai ---> us
    // us   --- Dai  ---> to
    function redeem(address from, address to, uint256 eDaiAmount)
        public onlyHolderOrDelegate(from, "EDai: Only Holder Or Delegate") lock override 
        returns (uint256)
    {
        require(
            isMature == true,
            "EDai: eDai is not mature"
        );
        _burn(from, eDaiAmount);                              // Burn eDai from `from`
        uint256 daiAmount = muld(eDaiAmount, chiGrowth());    // User gets interest for holding after maturity
        treasury.pullDai(to, daiAmount);                     // Give dai to `to`, from Treasury
        emit Redeemed(from, to, eDaiAmount, daiAmount);
        return daiAmount;
    }

    /// @dev Flash-mint eDai. Calls back on `IFlashMinter.executeOnFlashMint()`
    /// @param to Wallet to mint the eDai in.
    /// @param eDaiAmount Amount of eDai to mint.
    /// @param data User-defined data to pass on to `executeOnFlashMint()`
    function flashMint(address to, uint256 eDaiAmount, bytes calldata data) external lock override {
        _mint(to, eDaiAmount);
        IFlashMinter(msg.sender).executeOnFlashMint(to, eDaiAmount, data);
        _burn(to, eDaiAmount);
    }

    /// @dev Mint eDai. Only callable by Controller contracts.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param to Wallet to mint the eDai in.
    /// @param eDaiAmount Amount of eDai to mint.
    function mint(address to, uint256 eDaiAmount) public override onlyOrchestrated("EDai: Not Authorized") {
        _mint(to, eDaiAmount);
    }

    /// @dev Burn eDai. Only callable by Controller contracts.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param from Wallet to burn the eDai from.
    /// @param eDaiAmount Amount of eDai to burn.
    function burn(address from, uint256 eDaiAmount) public override onlyOrchestrated("EDai: Not Authorized") {
        _burn(from, eDaiAmount);
    }

    /// @dev Creates `eDaiAmount` tokens and assigns them to `to`, increasing the total supply, up to a limit of 2**112.
    /// @param to Wallet to mint the eDai in.
    /// @param eDaiAmount Amount of eDai to mint.
    function _mint(address to, uint256 eDaiAmount) internal override {
        super._mint(to, eDaiAmount);
        require(totalSupply() <= 5192296858534827628530496329220096, "EDai: Total supply limit exceeded"); // 2**112
    }
}
