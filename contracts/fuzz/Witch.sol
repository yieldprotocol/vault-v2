// Sources flattened with hardhat v2.2.0 https://hardhat.org

// File @yield-protocol/vault-interfaces/ILadle.sol@v2.0.22


pragma solidity ^0.8.0;


interface ILadle {
    /// @dev Allow liquidation contracts to move assets to wind down vaults
    function settle(bytes12 vaultId, address user, uint128 ink, uint128 art) external;
}


// File @yield-protocol/utils-v2/contracts/token/IERC20.sol@v2.2.1



pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


// File @yield-protocol/vault-interfaces/IFYToken.sol@v2.0.22


pragma solidity ^0.8.0;

interface IFYToken is IERC20 {
    /// @dev Asset that is returned on redemption. Also called underlying.
    function asset() external view returns (address);

    /// @dev Unix time at which redemption of fyToken for underlying are possible
    function maturity() external view returns (uint256);
    
    /// @dev Record price data at maturity
    function mature() external;

    /// @dev Burn fyToken after maturity for an amount of underlying.
    function redeem(address to, uint256 amount) external returns (uint256);

    /// @dev Mint fyToken.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param to Wallet to mint the fyToken in.
    /// @param fyTokenAmount Amount of fyToken to mint.
    function mint(address to, uint256 fyTokenAmount) external;

    /// @dev Burn fyToken.
    /// This function can only be called by other Yield contracts, not users directly.
    /// @param from Wallet to burn the fyToken from.
    /// @param fyTokenAmount Amount of fyToken to burn.
    function burn(address from, uint256 fyTokenAmount) external;
}


// File @yield-protocol/vault-interfaces/IOracle.sol@v2.0.22


pragma solidity ^0.8.0;

interface IOracle {

    /**
     * @notice The original source for the date
     * @return The address of the original source
     */
    function source() external view returns (address);

    /**
     * @notice Doesn't refresh the price, but returns the latest value available without doing any transactional operations:
     * eg, the price cached by the most recent call to `get()`.
     * @return price WAD-scaled - 18 dec places
     */
    function peek() external view returns (uint price, uint updateTime);

    /**
     * @notice Does whatever work or queries will yield the most up-to-date price, and returns it (typically also caching it
     * for `peek()` callers).
     * @return price WAD-scaled - 18 dec places
     */
    function get() external returns (uint price, uint updateTime);
}


// File @yield-protocol/vault-interfaces/DataTypes.sol@v2.0.22


pragma solidity ^0.8.0;


library DataTypes {
    struct Series {
        IFYToken fyToken;                                               // Redeemable token for the series.
        bytes6  baseId;                                                 // Asset received on redemption.
        uint32  maturity;                                               // Unix time at which redemption becomes possible.
        // bytes2 free
    }

    struct Debt {
        uint128 max;                                                    // Maximum debt accepted for a given underlying, across all series
        uint128 sum;                                                    // Current debt for a given underlying, across all series
    }

    struct SpotOracle {
        IOracle oracle;                                                 // Address for the spot price oracle
        uint32  ratio;                                                  // Collateralization ratio to multiply the price for
        // bytes8 free
    }

    struct Vault {
        address owner;
        bytes6  seriesId;                                                // Each vault is related to only one series, which also determines the underlying.
        bytes6  ilkId;                                                   // Asset accepted as collateral
    }

    struct Balances {
        uint128 art;                                                     // Debt amount
        uint128 ink;                                                     // Collateral amount
    }
}


// File @yield-protocol/vault-interfaces/ICauldron.sol@v2.0.22


pragma solidity ^0.8.0;



interface ICauldron {
    /// @dev Add a collateral to Cauldron
    // function addAsset(bytes6 id, address asset) external;

    /// @dev Add an underlying to Cauldron
    // function addAsset(address asset) external;

    /// @dev Add a series to Cauldron
    // function addSeries(bytes32 series, IERC20 asset, IFYToken fyToken) external;

    /// @dev Add a spot oracle to Cauldron
    // function setSpotOracle(IERC20 asset, IERC20 asset, IOracle oracle) external;

    /// @dev Add a chi oracle to Cauldron
    // function addChiOracle(IERC20 asset, IOracle oracle) external;

    /// @dev Add a rate oracle to Cauldron
    // function addRateOracle(IERC20 asset, IOracle oracle) external;

    /// @dev Spot price oracle for an underlying and collateral
    // function chiOracles(bytes6 asset, bytes6 asset) external returns (address);

    /// @dev Chi (savings rate) accruals oracle for an underlying
    // function chiOracles(bytes6 asset) external returns (address);

    /// @dev Rate (borrowing rate) accruals oracle for an underlying
    function rateOracles(bytes6 baseId) external view returns (IOracle);

    /// @dev An user can own one or more Vaults, with each vault being able to borrow from a single series.
    function vaults(bytes12 vault) external view returns (DataTypes.Vault memory);

    /// @dev Series available in Cauldron.
    function series(bytes6 seriesId) external view returns (DataTypes.Series memory);

    /// @dev Assets available in Cauldron.
    function assets(bytes6 assetsId) external view returns (address);

    /// @dev Each vault records debt and collateral balances_.
    function balances(bytes12 vault) external view returns (DataTypes.Balances memory);

    /// @dev Time at which a vault entered liquidation.
    function timestamps(bytes12 vault) external view returns (uint32);

    /// @dev Create a new vault, linked to a series (and therefore underlying) and up to 5 collateral types
    function build(address owner, bytes12 vaultId, bytes6 seriesId, bytes6 ilkId) external returns (DataTypes.Vault memory);

    /// @dev Destroy an empty vault. Used to recover gas costs.
    function destroy(bytes12 vault) external;

    /// @dev Change a vault series and/or collateral types.
    function tweak(bytes12 vaultId, bytes6 seriesId, bytes6 ilkId) external returns (DataTypes.Vault memory);

    /// @dev Give a vault to another user.
    function give(bytes12 vaultId, address user) external returns (DataTypes.Vault memory);

    /// @dev Move collateral and debt between vaults.
    function stir(bytes12 from, bytes12 to, uint128 ink, uint128 art) external returns (DataTypes.Balances memory, DataTypes.Balances memory);

    /// @dev Manipulate a vault debt and collateral.
    function pour(bytes12 vaultId, int128 ink, int128 art) external returns (DataTypes.Balances memory);

    /// @dev Change series and debt of a vault.
    /// The module calling this function also needs to buy underlying in the pool for the new series, and sell it in pool for the old series.
    function roll(bytes12 vaultId, bytes6 seriesId, uint128 art) external returns (DataTypes.Vault memory, DataTypes.Balances memory);

    /// @dev Give a non-timestamped vault to the caller, and timestamp it.
    /// To be used for liquidation engines.
    function grab(bytes12 vault) external;

    /// @dev Reduce debt and collateral from a vault, ignoring collateralization checks.
    function slurp(bytes12 vaultId, uint128 ink, uint128 art) external returns (DataTypes.Balances memory);

    // ==== Accounting ====

    /// @dev Record the borrowing rate at maturity for a series
    function mature(bytes6 seriesId) external;
    
    /// @dev Retrieve the rate accrual since maturity, maturing if necessary.
    function accrual(bytes6 seriesId) external returns (uint256);
    
    /// @dev Return the vault debt in underlying terms
    // function dues(bytes12 vault) external view returns (uint128 uart);

    /// @dev Return the capacity of the vault to borrow underlying assetd on the assets held
    // function value(bytes12 vault) external view returns (uint128 uart);

    /// @dev Return the collateralization level of a vault. It will be negative if undercollateralized.
    // function level(bytes12 vault) external view returns (int128);
}


// File contracts/math/WMul.sol


pragma solidity ^0.8.0;


library WMul {
    // Taken from https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
    /// @dev Multiply an amount by a fixed point factor with 18 decimals, rounds down.
    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * y;
        unchecked { z /= 1e18; }
    }
}


// File contracts/math/WDiv.sol


pragma solidity ^0.8.0;


library WDiv { // Fixed point arithmetic in 18 decimal units
    // Taken from https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
    /// @dev Divide an amount by a fixed point factor with 18 decimals
    function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = (x * 1e18) / y;
    }
}


// File contracts/math/WDivUp.sol


pragma solidity ^0.8.0;


library WDivUp { // Fixed point arithmetic in 18 decimal units
    // Taken from https://github.com/usmfum/USM/blob/master/contracts/WadMath.sol
    /// @dev Divide x and y, with y being fixed point. If both are integers, the result is a fixed point factor. Rounds up.
    function wdivup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x * 1e18 + y;
        unchecked { z -= 1; }
        z /= y;
    }
}


// File contracts/math/CastU256U128.sol


pragma solidity ^0.8.0;


library CastU256U128 {
    /// @dev Safely cast an uint256 to an uint128
    function u128(uint256 x) internal pure returns (uint128 y) {
        require (x <= type(uint128).max, "Cast overflow");
        y = uint128(x);
    }
}


// File contracts/Witch.sol


pragma solidity ^0.8.0;







contract Witch {
    using WMul for uint256;
    using WDiv for uint256;
    using WDivUp for uint256;
    using CastU256U128 for uint256;

    event Bought(address indexed buyer, bytes12 indexed vaultId, uint256 ink, uint256 art);
  
    uint256 constant public AUCTION_TIME = 4 * 60 * 60; // Time that auctions take to go to minimal price and stay there.
    ICauldron immutable public cauldron;
    ILadle immutable public ladle;

    constructor (ICauldron cauldron_, ILadle ladle_) {
        cauldron = cauldron_;
        ladle = ladle_;
    }

    /// @dev Put an undercollateralized vault up for liquidation.
    function grab(bytes12 vaultId) public {
        cauldron.grab(vaultId);
    }

    /// @dev Buy an amount of collateral off a vault in liquidation, paying at most `max` underlying.
    function buy(bytes12 vaultId, uint128 art, uint128 min) public {
        DataTypes.Balances memory balances_ = cauldron.balances(vaultId);

        require (balances_.art > 0, "Nothing to buy");                                      // Cheapest way of failing gracefully if given a non existing vault
        uint256 elapsed = uint32(block.timestamp) - cauldron.timestamps(vaultId);           // Auctions will malfunction on the 7th of February 2106, at 06:28:16 GMT, we should replace this contract before then.
        uint256 price;
        {
            // Price of a collateral unit, in underlying, at the present moment, for a given vault
            //
            //                ink       1      min(auction, elapsed)
            // price = 1 / (------- * (--- + -----------------------))
            //                art       2       2 * auction
            // solhint-disable-next-line var-name-mixedcase
            uint256 term1 = uint256(balances_.ink).wdiv(balances_.art);
            uint256 term2 = 1e18 / 2;
            uint256 dividend3 = AUCTION_TIME < elapsed ? AUCTION_TIME : elapsed;
            uint256 divisor3 = AUCTION_TIME * 2;
            uint256 term3 = dividend3.wdiv(divisor3);
            price = uint256(1e18).wdiv(term1.wmul(term2 + term3));
        }
        uint256 ink = uint256(art).wdivup(price);                                                    // Calculate collateral to sell. Using divdrup stops rounding from leaving 1 stray wei in vaults.
        require (ink >= min, "Not enough bought");

        ladle.settle(vaultId, msg.sender, ink.u128(), art);                                        // Move the assets
        if (balances_.art - art == 0 && balances_.ink - ink == 0) cauldron.destroy(vaultId);

        emit Bought(msg.sender, vaultId, ink, art);
    }
}
