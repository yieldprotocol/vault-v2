// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "./interfaces/ITreasury.sol";
import "./interfaces/IFYDai.sol";
import "./interfaces/IFlashMinter.sol";
import "./helpers/Delegable.sol";
import "./helpers/Orchestrated.sol";
import "./helpers/ERC20Permit.sol";


/**
 * @dev fyDai is an fyToken targeting Chai.
 * Each fyDai contract has a specific maturity time. One fyDai is worth one Chai at or after maturity time.
 * Redeeming an fyDai means burning it, and the contract will retrieve underlying from Treasury, with interest.
 * Minting and burning of fyDai is restricted to orchestrated contracts. Redeeming and flash-minting is allowed to anyone.
 */

contract FYDai is IFYDai, Orchestrated(), Delegable(), ERC20Permit  {

    event Redeemed(address indexed from, address indexed to, uint256 amount);

    uint256 constant internal MAX_TIME_TO_MATURITY = 126144000; // seconds in four years

    IVat public vat;
    IPot public pot;
    ITreasury public treasury;

    uint256 public override maturity;

    uint public override unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "FYDai: Locked");
        unlocked = 0;
        _;
        unlocked = 1;
    }
    
    /// @dev The constructor:
    /// Sets the name and symbol for the fyDai token.
    /// Sets the maturity date for the fyDai, in unix time.
    constructor(
        ITreasury treasury_,
        IERC20 underlying_,
        IOracle oracle_, // Underlying vs its interest-bearing version
        uint256 maturity_,
        string memory name,
        string memory symbol
    ) public ERC20Permit(name, symbol) {
        // solium-disable-next-line security/no-block-members
        require(maturity_ > now && maturity_ < now + MAX_TIME_TO_MATURITY, "FYDai: Invalid maturity");
        treasury = treasury_;
        underlying = underlying_;
        oracle = oracle_;
        maturity = maturity_;
    }

    /// @dev Burn fyDai and return their dai equivalent value, pulled from the Treasury
    /// During unwind, `treasury.pullDai()` will revert which is right.
    /// `from` needs to tell fyDai to approve the burning of the fyDai tokens.
    /// `from` can delegate to other addresses to redeem his fyDai and put the Dai proceeds in the `to` wallet.
    /// The collateral needed changes according to series maturity and MakerDAO rate and chi, depending on collateral type.
    /// @param from Wallet to burn fyDai from.
    /// @param to Wallet to put the Dai in.
    /// @param fyDaiAmount Amount of fyDai to burn.
    // from --- fyDai ---> us
    // us   --- Dai  ---> to
    function redeem(address from, address to, uint256 amount)
        public
        onlyHolderOrDelegate(from, "FYDai: Only Holder Or Delegate") lock override 
        returns (uint256)
    {
        require(
            block.timestamp >= maturity,
            "FYDai: fyDai is not mature"
        );
        _burn(from, amount);
        treasury.pull(to, amount * oracle.rateChange(maturity));
        emit Redeemed(from, to, amount);
        return amount;
    }

    /// @dev Flash-mint fyDai. Calls back on `IFlashMinter.executeOnFlashMint()`
    /// @param fyDaiAmount Amount of fyDai to mint.
    /// @param data User-defined data to pass on to `executeOnFlashMint()`
    function flashMint(uint256 fyDaiAmount, bytes calldata data) external lock override {
        require(totalSupply() + fyDaiAmount <= type(uint112).max, "FYDai: Total supply limit exceeded");
        _mint(msg.sender, fyDaiAmount);
        IFlashMinter(msg.sender).executeOnFlashMint(fyDaiAmount, data);
        _burn(msg.sender, fyDaiAmount);
    }

    /// @dev Mint fyDai. Only callable by Controller contracts.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param to Wallet to mint the fyDai in.
    /// @param fyDaiAmount Amount of fyDai to mint.
    function mint(address to, uint256 fyDaiAmount) public override onlyOrchestrated("FYDai: Not Authorized") {
        _mint(to, fyDaiAmount);
    }

    /// @dev Burn fyDai. Only callable by Controller contracts.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param from Wallet to burn the fyDai from.
    /// @param fyDaiAmount Amount of fyDai to burn.
    function burn(address from, uint256 fyDaiAmount) public override onlyOrchestrated("FYDai: Not Authorized") {
        _burn(from, fyDaiAmount);
    }
}
