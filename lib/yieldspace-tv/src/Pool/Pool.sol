// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.15;
import "./PoolImports.sol"; /*

   __     ___      _     _
   \ \   / (_)    | |   | |  ██████╗  ██████╗  ██████╗ ██╗        ███████╗ ██████╗ ██╗
    \ \_/ / _  ___| | __| |  ██╔══██╗██╔═══██╗██╔═══██╗██║        ██╔════╝██╔═══██╗██║
     \   / | |/ _ \ |/ _` |  ██████╔╝██║   ██║██║   ██║██║        ███████╗██║   ██║██║
      | |  | |  __/ | (_| |  ██╔═══╝ ██║   ██║██║   ██║██║        ╚════██║██║   ██║██║
      |_|  |_|\___|_|\__,_|  ██║     ╚██████╔╝╚██████╔╝███████╗██╗███████║╚██████╔╝███████╗
       yieldprotocol.com     ╚═╝      ╚═════╝  ╚═════╝ ╚══════╝╚═╝╚══════╝ ╚═════╝ ╚══════╝

                                                ┌─────────┐
                                                │no       │
                                                │lifeguard│
                                                └─┬─────┬─┘       ==+
                    be cool, stay in pool         │     │    =======+
                                             _____│_____│______    |+
                                      \  .-'"___________________`-.|+
                                        ( .'"                   '-.)+
                                        |`-..__________________..-'|+
                                        |                          |+
             .-:::::::::::-.            |                          |+      ┌──────────────┐
           .:::::::::::::::::.          |         ---  ---         |+      │$            $│
          :  _______  __   __ :        .|         (o)  (o)         |+.     │ ┌────────────┴─┐
         :: |       ||  | |  |::      /`|                          |+'\    │ │$            $│
        ::: |    ___||  |_|  |:::    / /|            [             |+\ \   │$│ ┌────────────┴─┐
        ::: |   |___ |       |:::   / / |        ----------        |+ \ \  └─┤ │$  ERC4626   $│
        ::: |    ___||_     _|:::.-" ;  \        \________/        /+  \ "--/│$│  Tokenized   │
        ::: |   |      |   |  ::),.-'    `-..__________________..-' +=  `---=└─┤ Vault Shares │
         :: |___|      |___|  ::=/              |    | |    |                  │$            $│
          :       TOKEN       :                 |    | |    |                  └──────────────┘
           `:::::::::::::::::'                  |    | |    |
             `-:::::::::::-'                    +----+ +----+
                `'''''''`                  _..._|____| |____| _..._
                                         .` "-. `%   | |    %` .-" `.
                                        /      \    .: :.     /      \
                                        '-..___|_..=:` `-:=.._|___..-'
*/

/// A Yieldspace AMM implementation for pools which provide liquidity and trading of fyTokens vs base tokens.
/// **The base tokens in this implementation are converted to ERC4626 compliant tokenized vault shares.**
/// See whitepaper and derived formulas: https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw
//
//  Useful terminology:
//    base - Example: DAI. The underlying token of the fyToken. Sometimes referred to as "asset" or "base".
//    shares - Example: yvDAI. Upon receipt, base is deposited (wrapped) in a tokenized vault.
//    c - Current price of shares in terms of base (in 64.64 bit)
//    mu - also called c0 is the initial c of shares at contract deployment
//    Reserves are tracked in shares * mu for consistency.
//
/// @title  Pool.sol
/// @dev    Uses ABDK 64.64 mathlib for precision and reduced gas.
/// @author Adapted by @devtooligan from original work by @alcueca and UniswapV2. Maths and whitepaper by @aniemerg.
contract Pool is PoolEvents, IPool, ERC20Permit, AccessControl {
    /* LIBRARIES
     *****************************************************************************************************************/

    using Math for uint256;
    using Math64x64 for int128;
    using Math64x64 for uint256;
    using Cast for uint128;
    using Cast for uint256;
    using TransferHelper for IMaturingToken;
    using TransferHelper for IERC20Like;

    /* MODIFIERS
     *****************************************************************************************************************/

    /// Trading can only be done before maturity.
    modifier beforeMaturity() {
        if (block.timestamp >= maturity) revert AfterMaturity();
        _;
    }

    /* IMMUTABLES
     *****************************************************************************************************************/

    /// The fyToken for the corresponding base token. Ex. yvDAI's fyToken will be fyDAI. Even though we convert base
    /// in this contract to a wrapped tokenized vault (e.g. Yearn Vault Dai), the fyToken is still payable in
    /// the base token upon maturity.
    IMaturingToken public immutable fyToken;

    /// This pool accepts a pair of base and fyToken tokens.
    /// When these are deposited into a tokenized vault they become shares.
    /// It is an ERC20 token.
    IERC20Like public immutable baseToken;

    /// Decimals of base tokens (fyToken, lp token, and usually the sharesToken).
    uint256 public immutable baseDecimals;

    /// When base comes into this contract it is deposited into a 3rd party tokenized vault in return for shares.
    /// @dev For most of this contract, only the ERC20 functionality of the shares token is required. As such, shares
    /// are cast as "IERC20Like" and when that 4626 functionality is needed, they are recast as IERC4626.
    /// This wei, modules for non-4626 compliant base tokens can import this contract and override 4626 specific fn's.
    IERC20Like public immutable sharesToken;

    /// Time stretch == 1 / seconds in x years where x varies per contract (64.64)
    int128 public immutable ts;

    /// The normalization coefficient, the initial c value or price per 1 share of base (64.64)
    int128 public immutable mu;

    /// Pool's maturity date (not 64.64)
    uint32 public immutable maturity;

    /// Used to scale up to 18 decimals (not 64.64)
    uint96 public immutable scaleFactor;

    /* STRUCTS
     *****************************************************************************************************************/

    struct Cache {
        uint16 g1Fee;
        uint104 sharesCached;
        uint104 fyTokenCached;
        uint32 blockTimestampLast;
    }

    /* STORAGE
     *****************************************************************************************************************/

    // The following 4 vars use one storage slot and can be retrieved in a Cache struct with getCache()

    /// This number is used to calculate the fees for buying/selling fyTokens.
    /// @dev This is a fp4 that represents a ratio out 1, where 1 is represented by 10000.
    uint16 public g1Fee;

    /// Shares reserves, cached.
    uint104 internal sharesCached;

    /// fyToken reserves, cached.
    uint104 internal fyTokenCached;

    /// block.timestamp of last time reserve caches were updated.
    uint32 internal blockTimestampLast;

    /// This is a LAGGING, time weighted sum of the fyToken:shares reserves ratio measured in ratio seconds.
    /// @dev Footgun 🔫 alert!  Be careful, this number is probably not what you need and it should normally be
    /// considered with blockTimestampLast. For consumption as a TWAR observation, use currentCumulativeRatio().
    /// In future pools, this function's visibility may be changed to internal.
    /// @return a fixed point factor with 27 decimals (ray).
    uint256 public cumulativeRatioLast;

    /* CONSTRUCTOR FUNCTIONS
     *****************************************************************************************************************/
    constructor(
        address sharesToken_, //    address of shares token
        address fyToken_, //  address of fyToken
        int128 ts_, //        time stretch(64.64)
        uint16 g1Fee_ //      fees (in bps) when buying fyToken
    )
        ERC20Permit(
            string(abi.encodePacked(IERC20Like(fyToken_).name(), " LP")),
            string(abi.encodePacked(IERC20Like(fyToken_).symbol(), "LP")),
            IERC20Like(fyToken_).decimals()
        )
    {
        /*  __   __        __  ___  __        __  ___  __   __
           /  ` /  \ |\ | /__`  |  |__) |  | /  `  |  /  \ |__)
           \__, \__/ | \| .__/  |  |  \ \__/ \__,  |  \__/ |  \ */

        // Set maturity with check to make sure its not 2107 yet.
        uint256 maturity_ = IMaturingToken(fyToken_).maturity();
        if (maturity_ > uint256(type(uint32).max)) revert MaturityOverflow();
        maturity = uint32(maturity_);

        // Set sharesToken.
        sharesToken = IERC20Like(sharesToken_);

        // Cache baseToken to save loads of SLOADs.
        IERC20Like baseToken_ = _getBaseAsset(sharesToken_);

        // Call approve hook for sharesToken.
        _approveSharesToken(baseToken_, sharesToken_);

        // NOTE: LP tokens, baseToken and fyToken should have the same decimals.  Within this core contract, it is
        // presumed that sharesToken also has the same decimals. If this is not the case, a separate module must be
        // used to overwrite _getSharesBalance() and other affected functions (see PoolEuler.sol for example).
        baseDecimals = baseToken_.decimals();

        // Set other immutables.
        baseToken = baseToken_;
        fyToken = IMaturingToken(fyToken_);
        ts = ts_;
        scaleFactor = uint96(10**(18 - uint96(baseDecimals))); // No more than 18 decimals allowed, reverts on underflow.

        // Set mu with check for 0.
        if ((mu = _getC()) == 0) {
            revert MuCannotBeZero();
        }

        // Set g1Fee state variable with out of bounds check.
        if ((g1Fee = g1Fee_) > 10000) revert InvalidFee(g1Fee_);
        emit FeesSet(g1Fee_);
    }

    /// This is used by the constructor to give max approval to sharesToken.
    /// @dev This should be overridden by modules if needed.
    /// @dev safeAprove will revert approve is unsuccessful
    function _approveSharesToken(IERC20Like baseToken_, address sharesToken_) internal virtual {
        baseToken_.safeApprove(sharesToken_, type(uint256).max);
    }

    /// This is used by the constructor to set the base token as immutable.
    /// @dev This should be overridden by modules.
    /// We use the IERC20Like interface, but this should be an ERC20 asset per EIP4626.
    function _getBaseAsset(address sharesToken_) internal virtual returns (IERC20Like) {
        return IERC20Like(address(IERC4626(sharesToken_).asset()));
    }

    /* LIQUIDITY FUNCTIONS

        ┌─────────────────────────────────────────────────┐
        │  mint, new life. gm!                            │
        │  buy, sell, mint more, trade, trade -- stop     │
        │  mature, burn. gg~                              │
        │                                                 │
        │ "Watashinojinsei (My Life)" - haiku by Poolie   │
        └─────────────────────────────────────────────────┘

     *****************************************************************************************************************/

    /*mint
                                                                                              v
         ___                                                                           \            /
         |_ \_/                   ┌───────────────────────────────┐
         |   |                    │                               │                 `    _......._     '   gm!
                                 \│                               │/                  .-:::::::::::-.
           │                     \│                               │/             `   :    __    ____ :   /
           └───────────────►      │            mint               │                 ::   / /   / __ \::
                                  │                               │  ──────▶    _   ::  / /   / /_/ /::   _
           ┌───────────────►      │                               │                 :: / /___/ ____/ ::
           │                     /│                               │\                ::/_____/_/      ::
                                 /│                               │\             '   :               :   `
         B A S E                  │                      \(^o^)/  │                   `-:::::::::::-'
                                  │                     Pool.sol  │                 ,    `'''''''`     .
                                  └───────────────────────────────┘
                                                                                       /            \
                                                                                              ^
    */
    /// Mint liquidity tokens in exchange for adding base and fyToken
    /// The amount of liquidity tokens to mint is calculated from the amount of unaccounted for fyToken in this contract.
    /// A proportional amount of asset tokens need to be present in this contract, also unaccounted for.
    /// @dev _totalSupply > 0 check important here to prevent unauthorized initialization.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param minRatio Minimum ratio of shares to fyToken in the pool (fp18).
    /// @param maxRatio Maximum ratio of shares to fyToken in the pool (fp18).
    /// @return baseIn The amount of base found in the contract that was used for the mint.
    /// @return fyTokenIn The amount of fyToken found that was used for the mint
    /// @return lpTokensMinted The amount of LP tokens minted.
    function mint(
        address to,
        address remainder,
        uint256 minRatio,
        uint256 maxRatio
    )
        external
        virtual
        override
        returns (
            uint256 baseIn,
            uint256 fyTokenIn,
            uint256 lpTokensMinted
        )
    {
        if (_totalSupply == 0) revert NotInitialized();

        (baseIn, fyTokenIn, lpTokensMinted) = _mint(to, remainder, 0, minRatio, maxRatio);
    }

    //  ╦┌┐┌┬┌┬┐┬┌─┐┬  ┬┌─┐┌─┐  ╔═╗┌─┐┌─┐┬
    //  ║││││ │ │├─┤│  │┌─┘├┤   ╠═╝│ ││ ││
    //  ╩┘└┘┴ ┴ ┴┴ ┴┴─┘┴└─┘└─┘  ╩  └─┘└─┘┴─┘
    /// @dev This is the exact same as mint() but with auth added and skip the supply > 0 check
    /// and checks instead that supply == 0.
    /// This intialize mechanism is different than UniV2.  Tokens addresses are added at contract creation.
    /// This pool is considered initialized after the first LP token is minted.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @return baseIn The amount of base found that was used for the mint.
    /// @return fyTokenIn The amount of fyToken found that was used for the mint
    /// @return lpTokensMinted The amount of LP tokens minted.
    function init(address to)
        external
        virtual
        auth
        returns (
            uint256 baseIn,
            uint256 fyTokenIn,
            uint256 lpTokensMinted
        )
    {
        if (_totalSupply != 0) revert Initialized();

        // address(this) used for the remainder, but actually this parameter is not used at all in this case because
        // there will never be any left over base in this case
        (baseIn, fyTokenIn, lpTokensMinted) = _mint(to, address(this), 0, 0, type(uint256).max);

        emit gm();
    }

    /* mintWithBase
                                                                                             V
                                  ┌───────────────────────────────┐                   \            /
                                  │                               │                 `    _......._     '   gm!
                                 \│                               │/                  .-:::::::::::-.
                                 \│                               │/             `   :    __    ____ :   /
                                  │         mintWithBase          │                 ::   / /   / __ \::
         B A S E     ──────►      │                               │  ──────▶    _   ::  / /   / /_/ /::   _
                                  │                               │                 :: / /___/ ____/ ::
                                 /│                               │\                ::/_____/_/      ::
                                 /│                               │\             '   :               :   `
                                  │                      \(^o^)/  │                   `-:::::::::::-'
                                  │                     Pool.sol  │                 ,    `'''''''`     .
                                  └───────────────────────────────┘                    /           \
                                                                                            ^
    */
    /// Mint liquidity tokens in exchange for adding only base.
    /// The amount of liquidity tokens is calculated from the amount of fyToken to buy from the pool.
    /// The base tokens need to be previously transferred and present in this contract.
    /// @dev _totalSupply > 0 check important here to prevent minting before initialization.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any leftover base at the end.
    /// @param fyTokenToBuy Amount of `fyToken` being bought in the Pool, from this we calculate how much base it will be taken in.
    /// @param minRatio Minimum ratio of shares to fyToken in the pool (fp18).
    /// @param maxRatio Maximum ratio of shares to fyToken in the pool (fp18).
    /// @return baseIn The amount of base found that was used for the mint.
    /// @return fyTokenIn The amount of fyToken found that was used for the mint
    /// @return lpTokensMinted The amount of LP tokens minted.
    function mintWithBase(
        address to,
        address remainder,
        uint256 fyTokenToBuy,
        uint256 minRatio,
        uint256 maxRatio
    )
        external
        virtual
        override
        returns (
            uint256 baseIn,
            uint256 fyTokenIn,
            uint256 lpTokensMinted
        )
    {
        if (_totalSupply == 0) revert NotInitialized();
        (baseIn, fyTokenIn, lpTokensMinted) = _mint(to, remainder, fyTokenToBuy, minRatio, maxRatio);
    }

    /// This is the internal function called by the external mint functions.
    /// Mint liquidity tokens, with an optional internal trade to buy fyToken beforehand.
    /// The amount of liquidity tokens is calculated from the amount of fyTokenToBuy from the pool,
    /// plus the amount of extra, unaccounted for fyToken in this contract.
    /// The base tokens also need to be previously transferred and present in this contract.
    /// Only usable before maturity.
    /// @dev Warning: This fn does not check if supply > 0 like the external functions do.
    /// This function overloads the ERC20._mint(address, uint) function.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param remainder Wallet receiving any surplus base.
    /// @param fyTokenToBuy Amount of `fyToken` being bought in the Pool.
    /// @param minRatio Minimum ratio of shares to fyToken in the pool (fp18).
    /// @param maxRatio Maximum ratio of shares to fyToken in the pool (fp18).
    /// @return baseIn The amount of base found that was used for the mint.
    /// @return fyTokenIn The amount of fyToken found that was used for the mint
    /// @return lpTokensMinted The amount of LP tokens minted.
    function _mint(
        address to,
        address remainder,
        uint256 fyTokenToBuy,
        uint256 minRatio,
        uint256 maxRatio
    )
        internal
        beforeMaturity
        returns (
            uint256 baseIn,
            uint256 fyTokenIn,
            uint256 lpTokensMinted
        )
    {
        // Wrap all base found in this contract.
        baseIn = baseToken.balanceOf(address(this));

        _wrap(address(this));

        // Gather data
        uint256 supply = _totalSupply;
        Cache memory cache = _getCache();
        uint256 realFYTokenCached_ = cache.fyTokenCached - supply; // The fyToken cache includes the virtual fyToken, equal to the supply
        uint256 sharesBalance = _getSharesBalance();

        // Check the burn wasn't sandwiched
        if (realFYTokenCached_ != 0) {
            if (
                uint256(cache.sharesCached).wdiv(realFYTokenCached_) < minRatio ||
                uint256(cache.sharesCached).wdiv(realFYTokenCached_) > maxRatio
            ) revert SlippageDuringMint(uint256(cache.sharesCached).wdiv(realFYTokenCached_), minRatio, maxRatio);
        } else if (maxRatio < type(uint256).max) {
            revert SlippageDuringMint(type(uint256).max, minRatio, maxRatio);
        }

        // Calculate token amounts
        uint256 sharesIn;
        if (supply == 0) {
            // **First mint**
            // Initialize at 1 pool token
            sharesIn = sharesBalance;
            lpTokensMinted = _mulMu(sharesIn);
        } else if (realFYTokenCached_ == 0) {
            // Edge case, no fyToken in the Pool after initialization
            sharesIn = sharesBalance - cache.sharesCached;
            lpTokensMinted = (supply * sharesIn) / cache.sharesCached;
        } else {
            // There is an optional virtual trade before the mint
            uint256 sharesToSell;
            if (fyTokenToBuy != 0) {
                sharesToSell = _buyFYTokenPreview(
                    fyTokenToBuy.u128(),
                    cache.sharesCached,
                    cache.fyTokenCached,
                    _computeG1(cache.g1Fee)
                );
            }

            // We use all the available fyTokens, plus optional virtual trade. Surplus is in base tokens.
            fyTokenIn = fyToken.balanceOf(address(this)) - realFYTokenCached_;
            lpTokensMinted = (supply * (fyTokenToBuy + fyTokenIn)) / (realFYTokenCached_ - fyTokenToBuy);

            sharesIn = sharesToSell + ((cache.sharesCached + sharesToSell) * lpTokensMinted) / supply;

            if ((sharesBalance - cache.sharesCached) < sharesIn) {
                revert NotEnoughBaseIn(_unwrapPreview(sharesBalance - cache.sharesCached), _unwrapPreview(sharesIn));
            }
        }

        // Update TWAR
        _update(
            (cache.sharesCached + sharesIn).u128(),
            (cache.fyTokenCached + fyTokenIn + lpTokensMinted).u128(), // Include "virtual" fyToken from new minted LP tokens
            cache.sharesCached,
            cache.fyTokenCached
        );

        // Execute mint
        _mint(to, lpTokensMinted);

        // Return any unused base tokens
        if (sharesBalance > cache.sharesCached + sharesIn) _unwrap(remainder);

        // confirm new virtual fyToken balance is not less than new supply
        if ((cache.fyTokenCached + fyTokenIn + lpTokensMinted) < supply + lpTokensMinted) {
            revert FYTokenCachedBadState();
        }

        emit Liquidity(
            maturity,
            msg.sender,
            to,
            address(0),
            -(baseIn.i256()),
            -(fyTokenIn.i256()),
            lpTokensMinted.i256()
        );
    }

    /* burn
                        (   (
                        )    (
                   (  (|   (|  )
                )   )\/ ( \/(( (    gg            ___
                ((  /     ))\))))\      ┌~~~~~~►  |_ \_/
                 )\(          |  )      │         |   |
                /:  | __    ____/:      │
                ::   / /   / __ \::  ───┤
                ::  / /   / /_/ /::     │
                :: / /___/ ____/ ::     └~~~~~~►  B A S E
                ::/_____/_/      ::
                 :               :
                  `-:::::::::::-'
                     `'''''''`
    */
    /// Burn liquidity tokens in exchange for base and fyToken.
    /// The liquidity tokens need to be previously tranfsferred to this contract.
    /// @param baseTo Wallet receiving the base tokens.
    /// @param fyTokenTo Wallet receiving the fyTokens.
    /// @param minRatio Minimum ratio of shares to fyToken in the pool (fp18).
    /// @param maxRatio Maximum ratio of shares to fyToken in the pool (fp18).
    /// @return lpTokensBurned The amount of LP tokens burned.
    /// @return baseOut The amount of base tokens received.
    /// @return fyTokenOut The amount of fyTokens received.
    function burn(
        address baseTo,
        address fyTokenTo,
        uint256 minRatio,
        uint256 maxRatio
    )
        external
        virtual
        override
        returns (
            uint256 lpTokensBurned,
            uint256 baseOut,
            uint256 fyTokenOut
        )
    {
        (lpTokensBurned, baseOut, fyTokenOut) = _burn(baseTo, fyTokenTo, false, minRatio, maxRatio);
    }

    /* burnForBase

                        (   (
                        )    (
                    (  (|   (|  )
                 )   )\/ ( \/(( (    gg
                 ((  /     ))\))))\
                  )\(          |  )
                /:  | __    ____/:
                ::   / /   / __ \::   ~~~~~~~►   B A S E
                ::  / /   / /_/ /::
                :: / /___/ ____/ ::
                ::/_____/_/      ::
                 :               :
                  `-:::::::::::-'
                     `'''''''`
    */
    /// Burn liquidity tokens in exchange for base.
    /// The liquidity provider needs to have called `pool.approve`.
    /// Only usable before maturity.
    /// @param to Wallet receiving the base and fyToken.
    /// @param minRatio Minimum ratio of shares to fyToken in the pool (fp18).
    /// @param maxRatio Maximum ratio of shares to fyToken in the pool (fp18).
    /// @return lpTokensBurned The amount of lp tokens burned.
    /// @return baseOut The amount of base tokens returned.
    function burnForBase(
        address to,
        uint256 minRatio,
        uint256 maxRatio
    ) external virtual override beforeMaturity returns (uint256 lpTokensBurned, uint256 baseOut) {
        (lpTokensBurned, baseOut, ) = _burn(to, address(0), true, minRatio, maxRatio);
    }

    /// Burn liquidity tokens in exchange for base.
    /// The liquidity provider needs to have called `pool.approve`.
    /// @dev This function overloads the ERC20._burn(address, uint) function.
    /// @param baseTo Wallet receiving the base.
    /// @param fyTokenTo Wallet receiving the fyToken.
    /// @param tradeToBase Whether the resulting fyToken should be traded for base tokens.
    /// @param minRatio Minimum ratio of shares to fyToken in the pool (fp18).
    /// @param maxRatio Maximum ratio of shares to fyToken in the pool (fp18).
    /// @return lpTokensBurned The amount of pool tokens burned.
    /// @return baseOut The amount of base tokens returned.
    /// @return fyTokenOut The amount of fyTokens returned.
    function _burn(
        address baseTo,
        address fyTokenTo,
        bool tradeToBase,
        uint256 minRatio,
        uint256 maxRatio
    )
        internal
        returns (
            uint256 lpTokensBurned,
            uint256 baseOut,
            uint256 fyTokenOut
        )
    {
        // Gather data
        lpTokensBurned = _balanceOf[address(this)];
        uint256 supply = _totalSupply;

        Cache memory cache = _getCache();
        uint96 scaleFactor_ = scaleFactor;

        // The fyToken cache includes the virtual fyToken, equal to the supply.
        uint256 realFYTokenCached_ = cache.fyTokenCached - supply;

        // Check the burn wasn't sandwiched
        if (realFYTokenCached_ != 0) {
            if (
                (uint256(cache.sharesCached).wdiv(realFYTokenCached_) < minRatio) ||
                (uint256(cache.sharesCached).wdiv(realFYTokenCached_) > maxRatio)
            ) {
                revert SlippageDuringBurn(uint256(cache.sharesCached).wdiv(realFYTokenCached_), minRatio, maxRatio);
            }
        }

        // Calculate trade
        uint256 sharesOut = (lpTokensBurned * cache.sharesCached) / supply;
        fyTokenOut = (lpTokensBurned * realFYTokenCached_) / supply;

        if (tradeToBase) {
            sharesOut +=
                YieldMath.sharesOutForFYTokenIn( //                                This is a virtual sell
                    (cache.sharesCached - sharesOut.u128()) * scaleFactor_, //     Cache, minus virtual burn
                    (cache.fyTokenCached - fyTokenOut.u128()) * scaleFactor_, //  Cache, minus virtual burn
                    fyTokenOut.u128() * scaleFactor_, //                          Sell the virtual fyToken obtained
                    maturity - uint32(block.timestamp), //                         This can't be called after maturity
                    ts,
                    _computeG2(cache.g1Fee),
                    _getC(),
                    mu
                ) /
                scaleFactor_;
            fyTokenOut = 0;
        }

        // Update TWAR
        _update(
            (cache.sharesCached - sharesOut).u128(),
            (cache.fyTokenCached - fyTokenOut - lpTokensBurned).u128(), // Exclude "virtual" fyToken from new minted LP tokens
            cache.sharesCached,
            cache.fyTokenCached
        );

        // Burn and transfer
        _burn(address(this), lpTokensBurned); // This is calling the actual ERC20 _burn.
        baseOut = _unwrap(baseTo);

        if (fyTokenOut != 0) fyToken.safeTransfer(fyTokenTo, fyTokenOut);

        // confirm new virtual fyToken balance is not less than new supply
        if ((cache.fyTokenCached - fyTokenOut - lpTokensBurned) < supply - lpTokensBurned) {
            revert FYTokenCachedBadState();
        }

        emit Liquidity(
            maturity,
            msg.sender,
            baseTo,
            fyTokenTo,
            baseOut.i256(),
            fyTokenOut.i256(),
            -(lpTokensBurned.i256())
        );

        if (supply == lpTokensBurned && block.timestamp >= maturity) {
            emit gg();
        }
    }

    /* TRADING FUNCTIONS
     ****************************************************************************************************************/

    /* buyBase

                         I want to buy `uint128 baseOut` worth of base tokens.
             _______     I've transferred you some fyTokens -- that should be enough.
            /   GUY \         .:::::::::::::::::.
     (^^^|   \===========    :  _______  __   __ :                 ┌─────────┐
      \(\/    | _  _ |      :: |       ||  | |  |::                │no       │
       \ \   (. o  o |     ::: |    ___||  |_|  |:::               │lifeguard│
        \ \   |   ~  |     ::: |   |___ |       |:::               └─┬─────┬─┘       ==+
        \  \   \ == /      ::: |    ___||_     _|::      ok guy      │     │    =======+
         \  \___|  |___    ::: |   |      |   |  :::            _____│_____│______    |+
          \ /   \__/   \    :: |___|      |___|  ::         .-'"___________________`-.|+
           \            \    :                   :         ( .'"                   '-.)+
            --|  GUY |\_/\  / `:::::::::::::::::'          |`-..__________________..-'|+
              |      | \  \/ /  `-:::::::::::-'            |                          |+
              |      |  \   /      `'''''''`               |                          |+
              |      |   \_/                               |       ---     ---        |+
              |______|                                     |       (o )    (o )       |+
              |__GG__|             ┌──────────────┐      /`|                          |+
              |      |             │$            $│     / /|            [             |+
              |  |   |             │   B A S E    │    / / |        ----------        |+
              |  |  _|             │   baseOut    │\.-" ;  \        \________/        /+
              |  |  |              │$            $│),.-'    `-..__________________..-' +=
              |  |  |              └──────────────┘                |    | |    |
              (  (  |                                              |    | |    |
              |  |  |                                              |    | |    |
              |  |  |                                              T----T T----T
             _|  |  |                                         _..._L____J L____J _..._
            (_____[__)                                      .` "-. `%   | |    %` .-" `.
                                                           /      \    .: :.     /      \
                                                           '-..___|_..=:` `-:=.._|___..-'
    */
    /// Buy base with fyToken.
    /// The trader needs to have transferred in the necessary amount of fyTokens in advance.
    /// @param to Wallet receiving the base being bought.
    /// @param baseOut Amount of base being bought that will be deposited in `to` wallet.
    /// @param max This has been deprecated and was left in for backwards compatibility.
    /// @return fyTokenIn Amount of fyToken that will be taken from caller.
    function buyBase(
        address to,
        uint128 baseOut,
        uint128 max
    ) external virtual override returns (uint128 fyTokenIn) {
        // Calculate trade and cache values
        uint128 fyTokenBalance = _getFYTokenBalance();
        Cache memory cache = _getCache();

        uint128 sharesOut = _wrapPreview(baseOut).u128();
        fyTokenIn = _buyBasePreview(sharesOut, cache.sharesCached, cache.fyTokenCached, _computeG2(cache.g1Fee));

        // Checks
        if (fyTokenBalance - cache.fyTokenCached < fyTokenIn) {
            revert NotEnoughFYTokenIn(fyTokenBalance - cache.fyTokenCached, fyTokenIn);
        }

        // Update TWAR
        _update(
            cache.sharesCached - sharesOut,
            cache.fyTokenCached + fyTokenIn,
            cache.sharesCached,
            cache.fyTokenCached
        );

        // Transfer
        _unwrap(to);

        emit Trade(maturity, msg.sender, to, baseOut.i128(), -(fyTokenIn.i128()));
    }

    /// Returns how much fyToken would be required to buy `baseOut` base.
    /// @dev Note: This fn takes baseOut as a param while the internal fn takes sharesOut.
    /// @param baseOut Amount of base hypothetically desired.
    /// @return fyTokenIn Amount of fyToken hypothetically required.
    function buyBasePreview(uint128 baseOut) external view virtual override returns (uint128 fyTokenIn) {
        Cache memory cache = _getCache();
        fyTokenIn = _buyBasePreview(
            _wrapPreview(baseOut).u128(),
            cache.sharesCached,
            cache.fyTokenCached,
            _computeG2(cache.g1Fee)
        );
    }

    /// Returns how much fyToken would be required to buy `sharesOut`.
    /// @dev Note: This fn takes sharesOut as a param while the external fn takes baseOut.
    function _buyBasePreview(
        uint128 sharesOut,
        uint104 sharesBalance,
        uint104 fyTokenBalance,
        int128 g2_
    ) internal view beforeMaturity returns (uint128 fyTokenIn) {
        uint96 scaleFactor_ = scaleFactor;
        fyTokenIn =
            YieldMath.fyTokenInForSharesOut(
                sharesBalance * scaleFactor_,
                fyTokenBalance * scaleFactor_,
                sharesOut * scaleFactor_,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g2_,
                _getC(),
                mu
            ) /
            scaleFactor_;
    }

    /*buyFYToken

                         I want to buy `uint128 fyTokenOut` worth of fyTokens.
             _______     I've transferred you some base tokens -- that should be enough.
            /   GUY \                                                 ┌─────────┐
     (^^^|   \===========  ┌──────────────┐                           │no       │
      \(\/    | _  _ |     │$            $│                           │lifeguard│
       \ \   (. o  o |     │ ┌────────────┴─┐                         └─┬─────┬─┘       ==+
        \ \   |   ~  |     │ │$            $│   hmm, let's see here     │     │    =======+
        \  \   \ == /      │ │   B A S E    │                      _____│_____│______    |+
         \  \___|  |___    │$│              │                  .-'"___________________`-.|+
          \ /   \__/   \   └─┤$            $│                 ( .'"                   '-.)+
           \            \    └──────────────┘                 |`-..__________________..-'|+
            --|  GUY |\_/\  / /                               |                          |+
              |      | \  \/ /                                |                          |+
              |      |  \   /         _......._             /`|       ---     ---        |+
              |      |   \_/       .-:::::::::::-.         / /|       (o )    (o )       |+
              |______|           .:::::::::::::::::.      / / |                          |+
              |__GG__|          :  _______  __   __ : _.-" ;  |            [             |+
              |      |         :: |       ||  | |  |::),.-'   |        ----------        |+
              |  |   |        ::: |    ___||  |_|  |:::/      \        \________/        /+
              |  |  _|        ::: |   |___ |       |:::        `-..__________________..-' +=
              |  |  |         ::: |    ___||_     _|:::               |    | |    |
              |  |  |         ::: |   |      |   |  :::               |    | |    |
              (  (  |          :: |___|      |___|  ::                |    | |    |
              |  |  |           :     fyTokenOut    :                 T----T T----T
              |  |  |            `:::::::::::::::::'             _..._L____J L____J _..._
             _|  |  |              `-:::::::::::-'             .` "-. `%   | |    %` .-" `.
            (_____[__)                `'''''''`               /      \    .: :.     /      \
                                                              '-..___|_..=:` `-:=.._|___..-'
    */
    /// Buy fyToken with base.
    /// The trader needs to have transferred in the correct amount of base tokens in advance.
    /// @param to Wallet receiving the fyToken being bought.
    /// @param fyTokenOut Amount of fyToken being bought that will be deposited in `to` wallet.
    /// @param max  This has been deprecated and was left in for backwards compatibility.
    /// @return baseIn Amount of base that will be used.
    function buyFYToken(
        address to,
        uint128 fyTokenOut,
        uint128 max
    ) external virtual override returns (uint128 baseIn) {
        // Wrap any base assets found in contract.
        _wrap(address(this));

        // Calculate trade
        uint128 sharesBalance = _getSharesBalance();
        Cache memory cache = _getCache();
        uint128 sharesIn = _buyFYTokenPreview(
            fyTokenOut,
            cache.sharesCached,
            cache.fyTokenCached,
            _computeG1(cache.g1Fee)
        );
        baseIn = _unwrapPreview(sharesIn).u128();

        // Checks
        if (sharesBalance - cache.sharesCached < sharesIn)
            revert NotEnoughBaseIn(_unwrapPreview(sharesBalance - cache.sharesCached), baseIn);

        // Update TWAR
        _update(
            cache.sharesCached + sharesIn,
            cache.fyTokenCached - fyTokenOut,
            cache.sharesCached,
            cache.fyTokenCached
        );

        // Transfer
        fyToken.safeTransfer(to, fyTokenOut);

        // confirm new virtual fyToken balance is not less than new supply
        if ((cache.fyTokenCached - fyTokenOut) < _totalSupply) {
            revert FYTokenCachedBadState();
        }

        emit Trade(maturity, msg.sender, to, -(baseIn.i128()), fyTokenOut.i128());
    }

    /// Returns how much base would be required to buy `fyTokenOut`.
    /// @param fyTokenOut Amount of fyToken hypothetically desired.
    /// @dev Note: This returns an amount in base.  The internal fn returns amount of shares.
    /// @return baseIn Amount of base hypothetically required.
    function buyFYTokenPreview(uint128 fyTokenOut) external view virtual override returns (uint128 baseIn) {
        Cache memory cache = _getCache();
        uint128 sharesIn = _buyFYTokenPreview(
            fyTokenOut,
            cache.sharesCached,
            cache.fyTokenCached,
            _computeG1(cache.g1Fee)
        );

        baseIn = _unwrapPreview(sharesIn).u128();
    }

    /// Returns how many shares are required to buy `fyTokenOut` fyTokens.
    /// @dev Note: This returns an amount in shares.  The external fn returns amount of base.
    function _buyFYTokenPreview(
        uint128 fyTokenOut,
        uint128 sharesBalance,
        uint128 fyTokenBalance,
        int128 g1_
    ) internal view beforeMaturity returns (uint128 sharesIn) {
        uint96 scaleFactor_ = scaleFactor;

        sharesIn =
            YieldMath.sharesInForFYTokenOut(
                sharesBalance * scaleFactor_,
                fyTokenBalance * scaleFactor_,
                fyTokenOut * scaleFactor_,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g1_,
                _getC(),
                mu
            ) /
            scaleFactor_;

        uint128 newSharesMulMu = _mulMu(sharesBalance + sharesIn).u128();
        if ((fyTokenBalance - fyTokenOut) < newSharesMulMu) {
            revert NegativeInterestRatesNotAllowed(fyTokenBalance - fyTokenOut, newSharesMulMu);
        }
    }

    /* sellBase

                         I've transfered you some base tokens.
             _______     Can you swap them for fyTokens?
            /   GUY \                                                 ┌─────────┐
     (^^^|   \===========  ┌──────────────┐                           │no       │
      \(\/    | _  _ |     │$            $│                           │lifeguard│
       \ \   (. o  o |     │ ┌────────────┴─┐                         └─┬─────┬─┘       ==+
        \ \   |   ~  |     │ │$            $│             can           │     │    =======+
        \  \   \ == /      │ │              │                      _____│_____│______    |+
         \  \___|  |___    │$│    baseIn    │                  .-'"___________________`-.|+
          \ /   \__/   \   └─┤$            $│                 ( .'"                   '-.)+
           \            \   ( └──────────────┘                 |`-..__________________..-'|+
            --|  GUY |\_/\  / /                               |                          |+
              |      | \  \/ /                                |                          |+
              |      |  \   /         _......._             /`|       ---     ---        |+
              |      |   \_/       .-:::::::::::-.         / /|       (o )    (o )       |+
              |______|           .:::::::::::::::::.      / / |                          |+
              |__GG__|          :  _______  __   __ : _.-" ;  |            [             |+
              |      |         :: |       ||  | |  |::),.-'   |        ----------        |+
              |  |   |        ::: |    ___||  |_|  |:::/      \        \________/        /+
              |  |  _|        ::: |   |___ |       |:::        `-..__________________..-' +=
              |  |  |         ::: |    ___||_     _|:::               |    | |    |
              |  |  |         ::: |   |      |   |  :::               |    | |    |
              (  (  |          :: |___|      |___|  ::                |    | |    |
              |  |  |           :      ????         :                 T----T T----T
              |  |  |            `:::::::::::::::::'             _..._L____J L____J _..._
             _|  |  |              `-:::::::::::-'             .` "-. `%   | |    %` .-" `.
            (_____[__)                `'''''''`               /      \    .: :.     /      \
                                                              '-..___|_..=:` `-:=.._|___..-'
    */
    /// Sell base for fyToken.
    /// The trader needs to have transferred the amount of base to sell to the pool before calling this fn.
    /// @param to Wallet receiving the fyToken being bought.
    /// @param min Minimum accepted amount of fyToken.
    /// @return fyTokenOut Amount of fyToken that will be deposited on `to` wallet.
    function sellBase(address to, uint128 min) external virtual override returns (uint128 fyTokenOut) {
        // Wrap any base assets found in contract.
        _wrap(address(this));

        // Calculate trade
        Cache memory cache = _getCache();
        uint104 sharesBalance = _getSharesBalance();
        uint128 sharesIn = sharesBalance - cache.sharesCached;
        fyTokenOut = _sellBasePreview(sharesIn, cache.sharesCached, cache.fyTokenCached, _computeG1(cache.g1Fee));

        // Check slippage
        if (fyTokenOut < min) revert SlippageDuringSellBase(fyTokenOut, min);

        // Update TWAR
        _update(sharesBalance, cache.fyTokenCached - fyTokenOut, cache.sharesCached, cache.fyTokenCached);

        // Transfer
        fyToken.safeTransfer(to, fyTokenOut);

        // confirm new virtual fyToken balance is not less than new supply
        if ((cache.fyTokenCached - fyTokenOut) < _totalSupply) {
            revert FYTokenCachedBadState();
        }

        emit Trade(maturity, msg.sender, to, -(_unwrapPreview(sharesIn).u128().i128()), fyTokenOut.i128());
    }

    /// Returns how much fyToken would be obtained by selling `baseIn`.
    /// @dev Note: This external fn takes baseIn while the internal fn takes sharesIn.
    /// @param baseIn Amount of base hypothetically sold.
    /// @return fyTokenOut Amount of fyToken hypothetically bought.
    function sellBasePreview(uint128 baseIn) external view virtual override returns (uint128 fyTokenOut) {
        Cache memory cache = _getCache();
        fyTokenOut = _sellBasePreview(
            _wrapPreview(baseIn).u128(),
            cache.sharesCached,
            cache.fyTokenCached,
            _computeG1(cache.g1Fee)
        );
    }

    /// Returns how much fyToken would be obtained by selling `sharesIn`.
    /// @dev Note: This internal fn takes sharesIn while the external fn takes baseIn.
    function _sellBasePreview(
        uint128 sharesIn,
        uint104 sharesBalance,
        uint104 fyTokenBalance,
        int128 g1_
    ) internal view beforeMaturity returns (uint128 fyTokenOut) {
        uint96 scaleFactor_ = scaleFactor;
        fyTokenOut =
            YieldMath.fyTokenOutForSharesIn(
                sharesBalance * scaleFactor_,
                fyTokenBalance * scaleFactor_,
                sharesIn * scaleFactor_,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g1_,
                _getC(),
                mu
            ) /
            scaleFactor_;

        uint128 newSharesMulMu = _mulMu(sharesBalance + sharesIn).u128();
        if ((fyTokenBalance - fyTokenOut) < newSharesMulMu) {
            revert NegativeInterestRatesNotAllowed(fyTokenBalance - fyTokenOut, newSharesMulMu);
        }
    }

    /*sellFYToken
                         I've transferred you some fyTokens.
             _______     Can you swap them for base?
            /   GUY \         .:::::::::::::::::.
     (^^^|   \===========    :  _______  __   __ :                 ┌─────────┐
      \(\/    | _  _ |      :: |       ||  | |  |::                │no       │
       \ \   (. o  o |     ::: |    ___||  |_|  |:::               │lifeguard│
        \ \   |   ~  |     ::: |   |___ |       |:::               └─┬─────┬─┘       ==+
        \  \   \ == /      ::: |    ___||_     _|:::     lfg         │     │    =======+
         \  \___|  |___    ::: |   |      |   |  :::            _____│_____│______    |+
          \ /   \__/   \    :: |___|      |___|  ::         .-'"___________________`-.|+
           \            \    :      fyTokenIn    :         ( .'"                   '-.)+
            --|  GUY |\_/\  / `:::::::::::::::::'          |`-..__________________..-'|+
              |      | \  \/ /  `-:::::::::::-'            |                          |+
              |      |  \   /      `'''''''`               |                          |+
              |      |   \_/                               |       ---     ---        |+
              |______|                                     |       (o )    (o )       |+
              |__GG__|             ┌──────────────┐      /`|                          |+
              |      |             │$            $│     / /|            [             |+
              |  |   |             │   B A S E    │    / / |        ----------        |+
              |  |  _|             │    ????      │\.-" ;  \        \________/        /+
              |  |  |              │$            $│),.-'    `-..__________________..-' +=
              |  |  |              └──────────────┘                |    | |    |
              (  (  |                                              |    | |    |
              |  |  |                                              |    | |    |
              |  |  |                                              T----T T----T
             _|  |  |                                         _..._L____J L____J _..._
            (_____[__)                                      .` "-. `%   | |    %` .-" `.
                                                           /      \    .: :.     /      \
                                                           '-..___|_..=:` `-:=.._|___..-'
    */
    /// Sell fyToken for base.
    /// The trader needs to have transferred the amount of fyToken to sell to the pool before in the same transaction.
    /// @param to Wallet receiving the base being bought.
    /// @param min Minimum accepted amount of base.
    /// @return baseOut Amount of base that will be deposited on `to` wallet.
    function sellFYToken(address to, uint128 min) external virtual override returns (uint128 baseOut) {
        // Calculate trade
        Cache memory cache = _getCache();
        uint104 fyTokenBalance = _getFYTokenBalance();
        uint128 fyTokenIn = fyTokenBalance - cache.fyTokenCached;
        uint128 sharesOut = _sellFYTokenPreview(
            fyTokenIn,
            cache.sharesCached,
            cache.fyTokenCached,
            _computeG2(cache.g1Fee)
        );

        // Update TWAR
        _update(cache.sharesCached - sharesOut, fyTokenBalance, cache.sharesCached, cache.fyTokenCached);

        // Transfer
        baseOut = _unwrap(to).u128();

        // Check slippage
        if (baseOut < min) revert SlippageDuringSellFYToken(baseOut, min);

        emit Trade(maturity, msg.sender, to, baseOut.i128(), -(fyTokenIn.i128()));
    }

    /// Returns how much base would be obtained by selling `fyTokenIn` fyToken.
    /// @dev Note: This external fn returns baseOut while the internal fn returns sharesOut.
    /// @param fyTokenIn Amount of fyToken hypothetically sold.
    /// @return baseOut Amount of base hypothetically bought.
    function sellFYTokenPreview(uint128 fyTokenIn) public view virtual returns (uint128 baseOut) {
        Cache memory cache = _getCache();
        uint128 sharesOut = _sellFYTokenPreview(
            fyTokenIn,
            cache.sharesCached,
            cache.fyTokenCached,
            _computeG2(cache.g1Fee)
        );
        baseOut = _unwrapPreview(sharesOut).u128();
    }

    /// Returns how much shares would be obtained by selling `fyTokenIn` fyToken.
    /// @dev Note: This internal fn returns sharesOut while the external fn returns baseOut.
    function _sellFYTokenPreview(
        uint128 fyTokenIn,
        uint104 sharesBalance,
        uint104 fyTokenBalance,
        int128 g2_
    ) internal view beforeMaturity returns (uint128 sharesOut) {
        uint96 scaleFactor_ = scaleFactor;

        sharesOut =
            YieldMath.sharesOutForFYTokenIn(
                sharesBalance * scaleFactor_,
                fyTokenBalance * scaleFactor_,
                fyTokenIn * scaleFactor_,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                g2_,
                _getC(),
                mu
            ) /
            scaleFactor_;
    }

    /* LIQUIDITY FUNCTIONS
     ****************************************************************************************************************/

    /// @inheritdoc IPool
    function maxFYTokenIn() public view override returns (uint128 fyTokenIn) {
        uint96 scaleFactor_ = scaleFactor;
        Cache memory cache = _getCache();
        fyTokenIn =
            YieldMath.maxFYTokenIn(
                cache.sharesCached * scaleFactor_,
                cache.fyTokenCached * scaleFactor_,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                _computeG2(cache.g1Fee),
                _getC(),
                mu
            ) /
            scaleFactor_;
    }

    /// @inheritdoc IPool
    function maxFYTokenOut() public view override returns (uint128 fyTokenOut) {
        uint96 scaleFactor_ = scaleFactor;
        Cache memory cache = _getCache();
        fyTokenOut =
            YieldMath.maxFYTokenOut(
                cache.sharesCached * scaleFactor_,
                cache.fyTokenCached * scaleFactor_,
                maturity - uint32(block.timestamp), // This can't be called after maturity
                ts,
                _computeG1(cache.g1Fee),
                _getC(),
                mu
            ) /
            scaleFactor_;
    }

    /// @inheritdoc IPool
    function maxBaseIn() public view override returns (uint128 baseIn) {
        uint96 scaleFactor_ = scaleFactor;
        Cache memory cache = _getCache();
        uint128 sharesIn = ((YieldMath.maxSharesIn(
            cache.sharesCached * scaleFactor_,
            cache.fyTokenCached * scaleFactor_,
            maturity - uint32(block.timestamp), // This can't be called after maturity
            ts,
            _computeG1(cache.g1Fee),
            _getC(),
            mu
        ) / 1e8) * 1e8) / scaleFactor_; // Shave 8 wei/decimals to deal with precision issues on the decimal functions

        baseIn = _unwrapPreview(sharesIn).u128();
    }

    /// @inheritdoc IPool
    function maxBaseOut() public view override returns (uint128 baseOut) {
        uint128 sharesOut = _getCache().sharesCached;
        baseOut = _unwrapPreview(sharesOut).u128();
    }

    /// @inheritdoc IPool
    function invariant() public view override returns (uint128 result) {
        uint96 scaleFactor_ = scaleFactor;
        Cache memory cache = _getCache();
        result =
            YieldMath.invariant(
                cache.sharesCached * scaleFactor_,
                cache.fyTokenCached * scaleFactor_,
                _totalSupply * scaleFactor_,
                maturity - uint32(block.timestamp),
                ts,
                _computeG2(cache.g1Fee),
                _getC(),
                mu
            ) /
            scaleFactor_;
    }

    /* WRAPPING FUNCTIONS
     ****************************************************************************************************************/

    /// Wraps any base asset tokens found in the contract, converting them to base tokenized vault shares.
    /// @dev This is provided as a convenience and uses the 4626 deposit method.
    /// @param receiver The address to which the wrapped tokens will be sent.
    /// @return shares The amount of wrapped tokens sent to the receiver.
    function wrap(address receiver) external returns (uint256 shares) {
        shares = _wrap(receiver);
    }

    /// Internal function for wrapping base tokens whichwraps the entire balance of base found in this contract.
    /// @dev This should be overridden by modules.
    /// @param receiver The address the wrapped tokens should be sent.
    /// @return shares The amount of wrapped tokens that are sent to the receiver.
    function _wrap(address receiver) internal virtual returns (uint256 shares) {
        uint256 assets = baseToken.balanceOf(address(this));
        if (assets == 0) {
            shares = 0;
        } else {
            shares = IERC4626(address(sharesToken)).deposit(assets, receiver);
        }
    }

    /// Preview how many shares will be received when depositing a given amount of base.
    /// @dev This should be overridden by modules.
    /// @param assets The amount of base tokens to preview the deposit.
    /// @return shares The amount of shares that would be returned from depositing.
    function wrapPreview(uint256 assets) external view returns (uint256 shares) {
        shares = _wrapPreview(assets);
    }

    /// Internal function to preview how many shares will be received when depositing a given amount of assets.
    /// @param assets The amount of base tokens to preview the deposit.
    /// @return shares The amount of shares that would be returned from depositing.
    function _wrapPreview(uint256 assets) internal view virtual returns (uint256 shares) {
        if (assets == 0) {
            shares = 0;
        } else {
            shares = IERC4626(address(sharesToken)).previewDeposit(assets);
        }
    }

    /// Unwraps base shares found unaccounted for in this contract, converting them to the base assets.
    /// @dev This is provided as a convenience and uses the 4626 redeem method.
    /// @param receiver The address to which the assets will be sent.
    /// @return assets The amount of asset tokens sent to the receiver.
    function unwrap(address receiver) external returns (uint256 assets) {
        assets = _unwrap(receiver);
    }

    /// Internal function for unwrapping unaccounted for base in this contract.
    /// @dev This should be overridden by modules.
    /// @param receiver The address the wrapped tokens should be sent.
    /// @return assets The amount of base assets sent to the receiver.
    function _unwrap(address receiver) internal virtual returns (uint256 assets) {
        uint256 surplus = _getSharesBalance() - sharesCached;
        if (surplus == 0) {
            assets = 0;
        } else {
            // The third param of the 4626 redeem fn, `owner`, is always this contract address.
            assets = IERC4626(address(sharesToken)).redeem(surplus, receiver, address(this));
        }
    }

    /// Preview how many asset tokens will be received when unwrapping a given amount of shares.
    /// @param shares The amount of shares to preview a redemption.
    /// @return assets The amount of base tokens that would be returned from redeeming.
    function unwrapPreview(uint256 shares) external view returns (uint256 assets) {
        assets = _unwrapPreview(shares);
    }

    /// Internal function to preview how base asset tokens will be received when unwrapping a given amount of shares.
    /// @dev This should be overridden by modules.
    /// @param shares The amount of shares to preview a redemption.
    /// @return assets The amount of base tokens that would be returned from redeeming.
    function _unwrapPreview(uint256 shares) internal view virtual returns (uint256 assets) {
        if (shares == 0) {
            assets = 0;
        } else {
            assets = IERC4626(address(sharesToken)).previewRedeem(shares);
        }
    }

    /* BALANCES MANAGEMENT AND ADMINISTRATIVE FUNCTIONS
       Note: The sync() function has been discontinued and removed.
     *****************************************************************************************************************/
    /*
                  _____________________________________
                   |o o o o o o o o o o o o o o o o o|
                   |o o o o o o o o o o o o o o o o o|
                   ||_|_|_|_|_|_|_|_|_|_|_|_|_|_|_|_||
                   || | | | | | | | | | | | | | | | ||
                   |o o o o o o o o o o o o o o o o o|
                   |o o o o o o o o o o o o o o o o o|
                   |o o o o o o o o o o o o o o o o o|
                   |o o o o o o o o o o o o o o o o o|
                  _|o_o_o_o_o_o_o_o_o_o_o_o_o_o_o_o_o|_
                          "Poolie's Abacus" - ejm */

    /// Calculates cumulative ratio as of current timestamp.  Can be consumed for TWAR observations.
    /// @dev See UniV2 implmentation: https://tinyurl.com/UniV2currentCumulativePrice
    /// @return currentCumulativeRatio_ is the cumulative ratio up to the current timestamp as ray.
    /// @return blockTimestampCurrent is the current block timestamp that the currentCumulativeRatio was computed with.
    function currentCumulativeRatio()
        external
        view
        virtual
        returns (uint256 currentCumulativeRatio_, uint256 blockTimestampCurrent)
    {
        blockTimestampCurrent = block.timestamp;
        uint256 timeElapsed;
        unchecked {
            timeElapsed = blockTimestampCurrent - blockTimestampLast;
        }

        // Multiply by 1e27 here so that r = t * y/x is a fixed point factor with 27 decimals
        currentCumulativeRatio_ = cumulativeRatioLast + (fyTokenCached * timeElapsed).rdiv(_mulMu(sharesCached));
    }

    /// Update cached values and, on the first call per block, update cumulativeRatioLast.
    /// cumulativeRatioLast is a LAGGING, time weighted sum of the reserves ratio which is updated as follows:
    ///
    ///   cumulativeRatioLast += old fyTokenReserves / old baseReserves * seconds elapsed since blockTimestampLast
    ///
    /// NOTE: baseReserves is calculated as mu * sharesReserves
    ///
    /// Example:
    ///   First mint creates a ratio of 1:1.
    ///   300 seconds later a trade occurs:
    ///     - cumulativeRatioLast is updated: 0 + 1/1 * 300 == 300
    ///     - sharesCached and fyTokenCached are updated with the new reserves amounts.
    ///     - This causes the ratio to skew to 1.1 / 1.
    ///   200 seconds later another trade occurs:
    ///     - NOTE: During this 200 seconds, cumulativeRatioLast == 300, which represents the "last" updated amount.
    ///     - cumulativeRatioLast is updated: 300 + 1.1 / 1 * 200 == 520
    ///     - sharesCached and fyTokenCached updated accordingly...etc.
    ///
    /// @dev See UniV2 implmentation: https://tinyurl.com/UniV2UpdateCumulativePrice
    function _update(
        uint128 sharesBalance,
        uint128 fyBalance,
        uint104 sharesCached_,
        uint104 fyTokenCached_
    ) internal {
        // No need to update and spend gas on SSTORE if reserves haven't changed.
        if (sharesBalance == sharesCached_ && fyBalance == fyTokenCached_) return;

        uint32 blockTimestamp = uint32(block.timestamp);
        uint256 timeElapsed = blockTimestamp - blockTimestampLast; // reverts on underflow

        uint256 oldCumulativeRatioLast = cumulativeRatioLast;
        uint256 newCumulativeRatioLast = oldCumulativeRatioLast;
        if (timeElapsed > 0 && fyTokenCached_ > 0 && sharesCached_ > 0) {
            // Multiply by 1e27 here so that r = t * y/x is a fixed point factor with 27 decimals
            newCumulativeRatioLast += (fyTokenCached_ * timeElapsed).rdiv(_mulMu(sharesCached_));
        }

        blockTimestampLast = blockTimestamp;
        cumulativeRatioLast = newCumulativeRatioLast;

        // Update the reserves caches
        uint104 newSharesCached = sharesBalance.u104();
        uint104 newFYTokenCached = fyBalance.u104();

        sharesCached = newSharesCached;
        fyTokenCached = newFYTokenCached;

        emit Sync(newSharesCached, newFYTokenCached, newCumulativeRatioLast);
    }

    /// Exposes the 64.64 factor used for determining fees.
    /// A value of 1 (in 64.64) means no fees.  g1 < 1 because it is used when selling base shares to the pool.
    /// @dev Converts state var cache.g1Fee(fp4) to a 64bit divided by 10,000
    /// Useful for external contracts that need to perform calculations related to pool.
    /// @return a 64bit factor used for applying fees when buying fyToken/selling base.
    function g1() external view returns (int128) {
        Cache memory cache = _getCache();
        return _computeG1(cache.g1Fee);
    }

    /// Returns the ratio of net proceeds after fees, for buying fyToken
    function _computeG1(uint16 g1Fee_) internal pure returns (int128) {
        return uint256(g1Fee_).divu(10000);
    }

    /// Exposes the 64.64 factor used for determining fees.
    /// A value of 1 means no fees.  g2 > 1 because it is used when selling fyToken to the pool.
    /// @dev Calculated by dividing 10,000 by state var cache.g1Fee(fp4) and converting to 64bit.
    /// Useful for external contracts that need to perform calculations related to pool.
    /// @return a 64bit factor used for applying fees when selling fyToken/buying base.
    function g2() external view returns (int128) {
        Cache memory cache = _getCache();
        return _computeG2(cache.g1Fee);
    }

    /// Returns the ratio of net proceeds after fees, for selling fyToken
    function _computeG2(uint16 g1Fee_) internal pure returns (int128) {
        // Divide 1 (64.64) by g1
        return uint256(10000).divu(g1Fee_);
    }

    /// Returns the shares balance with the same decimals as the underlying base asset.
    /// @dev NOTE: If the decimals of the share token does not match the base token, then the amount of shares returned
    /// will be adjusted to match the decimals of the base token.
    /// @return The current balance of the pool's shares tokens as uint128 for consistency with other functions.
    function getSharesBalance() external view returns (uint128) {
        return _getSharesBalance();
    }

    /// Returns the shares balance
    /// @dev NOTE: The decimals returned here must match the decimals of the base token.  If not, then this fn should
    // be overriden by modules.
    function _getSharesBalance() internal view virtual returns (uint104) {
        return sharesToken.balanceOf(address(this)).u104();
    }

    /// Returns the base balance.
    /// @dev Returns uint128 for backwards compatibility
    /// @return The current balance of the pool's base tokens.
    function getBaseBalance() external view returns (uint128) {
        return _getBaseBalance().u128();
    }

    /// Returns the base balance
    function _getBaseBalance() internal view virtual returns (uint256) {
        return (_getSharesBalance() * _getCurrentSharePrice()) / 10**baseDecimals;
    }

    /// Returns the base token current price.
    /// @return The price of 1 share of a tokenized vault token in terms of its base cast as uint256.
    function getCurrentSharePrice() external view returns (uint256) {
        return _getCurrentSharePrice();
    }

    /// Returns the base token current price.
    /// @dev This assumes the shares, base, and lp tokens all use the same decimals.
    /// This function should be overriden by modules.
    /// @return The price of 1 share of a tokenized vault token in terms of its base asset cast as uint256.
    function _getCurrentSharePrice() internal view virtual returns (uint256) {
        uint256 scalar = 10**baseDecimals;
        return IERC4626(address(sharesToken)).convertToAssets(scalar);
    }

    /// Returns current price of 1 share in 64bit.
    /// Useful for external contracts that need to perform calculations related to pool.
    /// @return The current price (as determined by the token) scalled to 18 digits and converted to 64.64.
    function getC() external view returns (int128) {
        return _getC();
    }

    /// Returns the c based on the current price
    function _getC() internal view returns (int128) {
        return (_getCurrentSharePrice() * scaleFactor).divu(1e18);
    }

    /// Returns the all storage vars except for cumulativeRatioLast
    /// @return Cached shares token balance.
    /// @return Cached virtual FY token balance which is the actual balance plus the pool token supply.
    /// @return Timestamp that balances were last cached.
    /// @return g1Fee  This is a fp4 number where 10_000 is 1.
    function getCache()
        public
        view
        virtual
        returns (
            uint104,
            uint104,
            uint32,
            uint16
        )
    {
        return (sharesCached, fyTokenCached, blockTimestampLast, g1Fee);
    }

    /// Returns the all storage vars except for cumulativeRatioLast
    /// @dev This returns the same info as external getCache but uses a struct to help with stack too deep.
    /// @return cache A struct containing:
    /// g1Fee a fp4 number where 10_000 is 1.
    /// Cached base token balance.
    /// Cached virtual FY token balance which is the actual balance plus the pool token supply.
    /// Timestamp that balances were last cached.

    function _getCache() internal view virtual returns (Cache memory cache) {
        cache = Cache(g1Fee, sharesCached, fyTokenCached, blockTimestampLast);
    }

    /// The "virtual" fyToken balance, which is the actual balance plus the pool token supply.
    /// @dev For more explanation about using the LP tokens as part of the virtual reserves see:
    /// https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw
    /// Returns uint128 for backwards compatibility
    /// @return The current balance of the pool's fyTokens plus the current balance of the pool's
    /// total supply of LP tokens as a uint104
    function getFYTokenBalance() public view virtual override returns (uint128) {
        return _getFYTokenBalance();
    }

    /// Returns the "virtual" fyToken balance, which is the real balance plus the pool token supply.
    function _getFYTokenBalance() internal view returns (uint104) {
        return (fyToken.balanceOf(address(this)) + _totalSupply).u104();
    }

    /// Returns mu multipled by given amount.
    /// @param amount Amount as standard fp number.
    /// @return product Return standard fp number retaining decimals of provided amount.
    function _mulMu(uint256 amount) internal view returns (uint256 product) {
        product = mu.mulu(amount);
    }

    /// Retrieve any shares tokens not accounted for in the cache.
    /// @param to Address of the recipient of the shares tokens.
    /// @return retrieved The amount of shares tokens sent.
    function retrieveShares(address to) external virtual override returns (uint128 retrieved) {
        retrieved = _getSharesBalance() - sharesCached; // Cache can never be above balances
        sharesToken.safeTransfer(to, retrieved);
    }

    /// Retrieve all base tokens found in this contract.
    /// @param to Address of the recipient of the base tokens.
    /// @return retrieved The amount of base tokens sent.
    function retrieveBase(address to) external virtual override returns (uint128 retrieved) {
        // This and most other pools do not keep any baseTokens, so retrieve everything.
        // Note: For PoolNonTv, baseToken == sharesToken so must override this fn.
        retrieved = baseToken.balanceOf(address(this)).u128();
        baseToken.safeTransfer(to, retrieved);
    }

    /// Retrieve any fyTokens not accounted for in the cache.
    /// @param to Address of the recipient of the fyTokens.
    /// @return retrieved The amount of fyTokens sent.
    function retrieveFYToken(address to) external virtual override returns (uint128 retrieved) {
        // related: https://twitter.com/transmissions11/status/1505994136389754880?s=20&t=1H6gvzl7DJLBxXqnhTuOVw
        retrieved = _getFYTokenBalance() - fyTokenCached; // Cache can never be above balances
        fyToken.safeTransfer(to, retrieved);
        // Now the balances match the cache, so no need to update the TWAR
    }

    /// Sets g1 as an fp4, g1 <= 1.0
    /// @dev These numbers are converted to 64.64 and used to calculate g1 by dividing them, or g2 from 1/g1
    function setFees(uint16 g1Fee_) public auth {
        if (g1Fee_ > 10000) {
            revert InvalidFee(g1Fee_);
        }
        g1Fee = g1Fee_;
        emit FeesSet(g1Fee_);
    }

    /// Returns baseToken.
    /// @dev This has been deprecated and may be removed in future pools.
    /// @return baseToken The base token for this pool.  The base of the shares and the fyToken.
    function base() external view returns (IERC20) {
        // Returns IERC20 instead of IERC20Like (IERC20Metadata) for backwards compatability.
        return IERC20(address(baseToken));
    }
}
