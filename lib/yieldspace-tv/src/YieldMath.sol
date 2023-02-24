// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;
/*
   __     ___      _     _
   \ \   / (_)    | |   | | ██╗   ██╗██╗███████╗██╗     ██████╗ ███╗   ███╗ █████╗ ████████╗██╗  ██╗
    \ \_/ / _  ___| | __| | ╚██╗ ██╔╝██║██╔════╝██║     ██╔══██╗████╗ ████║██╔══██╗╚══██╔══╝██║  ██║
     \   / | |/ _ \ |/ _` |  ╚████╔╝ ██║█████╗  ██║     ██║  ██║██╔████╔██║███████║   ██║   ███████║
      | |  | |  __/ | (_| |   ╚██╔╝  ██║██╔══╝  ██║     ██║  ██║██║╚██╔╝██║██╔══██║   ██║   ██╔══██║
      |_|  |_|\___|_|\__,_|    ██║   ██║███████╗███████╗██████╔╝██║ ╚═╝ ██║██║  ██║   ██║   ██║  ██║
       yieldprotocol.com       ╚═╝   ╚═╝╚══════╝╚══════╝╚═════╝ ╚═╝     ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝
*/

import {Exp64x64} from "./Exp64x64.sol";
import {Math64x64} from "./Math64x64.sol";
import {Cast} from "@yield-protocol/utils-v2/src/utils/Cast.sol";

/// Ethereum smart contract library implementing Yield Math model with yield bearing tokens.
/// @dev see Mikhail Vladimirov (ABDK) explanations of the math: https://hackmd.io/gbnqA3gCTR6z-F0HHTxF-A#Yield-Math
library YieldMath {
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;
    using Exp64x64 for int128;
    using Cast for uint256;
    using Cast for uint128;

    uint128 public constant WAD = 1e18;
    uint128 public constant ONE = 0x10000000000000000; //   In 64.64
    uint256 public constant MAX = type(uint128).max; //     Used for overflow checks

    /* CORE FUNCTIONS
     ******************************************************************************************************************/

    /* ----------------------------------------------------------------------------------------------------------------
                                              ┌───────────────────────────────┐                    .-:::::::::::-.
      ┌──────────────┐                        │                               │                  .:::::::::::::::::.
      │$            $│                       \│                               │/                :  _______  __   __ :
      │ ┌────────────┴─┐                     \│                               │/               :: |       ||  | |  |::
      │ │$            $│                      │    fyTokenOutForSharesIn      │               ::: |    ___||  |_|  |:::
      │$│ ┌────────────┴─┐     ────────▶      │                               │  ────────▶    ::: |   |___ |       |:::
      └─┤ │$            $│                    │                               │               ::: |    ___||_     _|:::
        │$│  `sharesIn`  │                   /│                               │\              ::: |   |      |   |  :::
        └─┤              │                   /│                               │\               :: |___|      |___|  ::
          │$            $│                    │                      \(^o^)/  │                 :       ????        :
          └──────────────┘                    │                     YieldMath │                  `:::::::::::::::::'
                                              └───────────────────────────────┘                    `-:::::::::::-'
    */
    /// Calculates the amount of fyToken a user would get for given amount of shares.
    /// https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param sharesIn shares amount to be traded
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
    /// @param g fee coefficient, multiplied by 2^64 -- sb under 1.0 for selling shares to pool
    /// @param c price of shares in terms of their base, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return fyTokenOut the amount of fyToken a user would get for given amount of shares
    function fyTokenOutForSharesIn(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // x
        uint128 sharesIn, // x == Δz
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128) {
        unchecked {
            require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");

            uint128 a = _computeA(timeTillMaturity, k, g);

            uint256 sum;
            {
                /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

                y = fyToken reserves
                z = shares reserves
                x = Δz (sharesIn)

                     y - (                         sum                           )^(   invA   )
                     y - ((    Za         ) + (  Ya  ) - (       Zxa           ) )^(   invA   )
                Δy = y - ( c/μ * (μz)^(1-t) +  y^(1-t) -  c/μ * (μz + μx)^(1-t)  )^(1 / (1 - t))

                */
                uint256 normalizedSharesReserves;
                require((normalizedSharesReserves = mu.mulu(sharesReserves)) <= MAX, "YieldMath: Rate overflow (nsr)");

                // za = c/μ * (normalizedSharesReserves ** a)
                // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
                // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
                uint256 za;
                require(
                    (za = c.div(mu).mulu(uint128(normalizedSharesReserves).pow(a, ONE))) <= MAX,
                    "YieldMath: Rate overflow (za)"
                );

                // ya = fyTokenReserves ** a
                // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
                // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
                uint256 ya = fyTokenReserves.pow(a, ONE);

                // normalizedSharesIn = μ * sharesIn
                uint256 normalizedSharesIn;
                require((normalizedSharesIn = mu.mulu(sharesIn)) <= MAX, "YieldMath: Rate overflow (nsi)");

                // zx = normalizedSharesReserves + sharesIn * μ
                uint256 zx;
                require((zx = normalizedSharesReserves + normalizedSharesIn) <= MAX, "YieldMath: Too many shares in");

                // zxa = c/μ * zx ** a
                // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
                // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
                uint256 zxa;
                require((zxa = c.div(mu).mulu(uint128(zx).pow(a, ONE))) <= MAX, "YieldMath: Rate overflow (zxa)");

                sum = za + ya - zxa;

                require(sum <= (za + ya), "YieldMath: Sum underflow");
            }

            // result = fyTokenReserves - (sum ** (1/a))
            // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
            // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
            uint256 fyTokenOut;
            require(
                (fyTokenOut = uint256(fyTokenReserves) - sum.u128().pow(ONE, a)) <= MAX,
                "YieldMath: Rounding error"
            );

            require(fyTokenOut <= fyTokenReserves, "YieldMath: > fyToken reserves");

            return uint128(fyTokenOut);
        }
    }

    /* ----------------------------------------------------------------------------------------------------------------
          .-:::::::::::-.                       ┌───────────────────────────────┐
        .:::::::::::::::::.                     │                               │
       :  _______  __   __ :                   \│                               │/              ┌──────────────┐
      :: |       ||  | |  |::                  \│                               │/              │$            $│
     ::: |    ___||  |_|  |:::                  │    sharesOutForFYTokenIn      │               │ ┌────────────┴─┐
     ::: |   |___ |       |:::   ────────▶      │                               │  ────────▶    │ │$            $│
     ::: |    ___||_     _|:::                  │                               │               │$│ ┌────────────┴─┐
     ::: |   |      |   |  :::                 /│                               │\              └─┤ │$            $│
      :: |___|      |___|  ::                  /│                               │\                │$│    SHARES    │
       :     `fyTokenIn`   :                    │                      \(^o^)/  │                 └─┤     ????     │
        `:::::::::::::::::'                     │                     YieldMath │                   │$            $│
          `-:::::::::::-'                       └───────────────────────────────┘                   └──────────────┘
    */
    /// Calculates the amount of shares a user would get for certain amount of fyToken.
    /// @param sharesReserves shares reserves amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param fyTokenIn fyToken amount to be traded
    /// @param timeTillMaturity time till maturity in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64
    /// @param g fee coefficient, multiplied by 2^64
    /// @param c price of shares in terms of Dai, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return amount of Shares a user would get for given amount of fyToken
    function sharesOutForFYTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenIn,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128) {
        unchecked {
            require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");
            return
                _sharesOutForFYTokenIn(
                    sharesReserves,
                    fyTokenReserves,
                    fyTokenIn,
                    _computeA(timeTillMaturity, k, g),
                    c,
                    mu
                );
        }
    }

    /// @dev Splitting sharesOutForFYTokenIn in two functions to avoid stack depth limits.
    function _sharesOutForFYTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenIn,
        uint128 a,
        int128 c,
        int128 mu
    ) private pure returns (uint128) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

            y = fyToken reserves
            z = shares reserves
            x = Δy (fyTokenIn)

                 z - (                                rightTerm                                              )
                 z - (invMu) * (      Za              ) + ( Ya   ) - (    Yxa      ) / (c / μ) )^(   invA    )
            Δz = z -   1/μ   * ( ( (c / μ) * (μz)^(1-t) +  y^(1-t) - (y + x)^(1-t) ) / (c / μ) )^(1 / (1 - t))

        */
        unchecked {
            // normalizedSharesReserves = μ * sharesReserves
            uint256 normalizedSharesReserves;
            require((normalizedSharesReserves = mu.mulu(sharesReserves)) <= MAX, "YieldMath: Rate overflow (nsr)");

            uint128 rightTerm;
            {
                uint256 zaYaYxa;
                {
                    // za = c/μ * (normalizedSharesReserves ** a)
                    // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
                    // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
                    uint256 za;
                    require(
                        (za = c.div(mu).mulu(uint128(normalizedSharesReserves).pow(a, ONE))) <= MAX,
                        "YieldMath: Rate overflow (za)"
                    );

                    // ya = fyTokenReserves ** a
                    // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
                    // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
                    uint256 ya = fyTokenReserves.pow(a, ONE);

                    // yxa = (fyTokenReserves + x) ** a   # x is aka Δy
                    // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
                    // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
                    uint256 yxa = (fyTokenReserves + fyTokenIn).pow(a, ONE);

                    require((zaYaYxa = (za + ya - yxa)) <= MAX, "YieldMath: Rate overflow (yxa)");
                }

                rightTerm = uint128( // Cast zaYaYxa/(c/μ).pow(1/a).div(μ) from int128 to uint128 - always positive
                    int128( // Cast zaYaYxa/(c/μ).pow(1/a) from uint128 to int128 - always < zaYaYxa/(c/μ)
                        uint128( // Cast zaYaYxa/(c/μ) from int128 to uint128 - always positive
                            zaYaYxa.divu(uint128(c.div(mu))) // Cast c/μ from int128 to uint128 - always positive
                        ).pow(uint128(ONE), a) // Cast 2^64 from int128 to uint128 - always positive
                    ).div(mu)
                );
            }
            require(rightTerm <= sharesReserves, "YieldMath: Rate underflow");

            return sharesReserves - rightTerm;
        }
    }

    /* ----------------------------------------------------------------------------------------------------------------
          .-:::::::::::-.                       ┌───────────────────────────────┐
        .:::::::::::::::::.                     │                               │              ┌──────────────┐
       :  _______  __   __ :                   \│                               │/             │$            $│
      :: |       ||  | |  |::                  \│                               │/             │ ┌────────────┴─┐
     ::: |    ___||  |_|  |:::                  │    fyTokenInForSharesOut      │              │ │$            $│
     ::: |   |___ |       |:::   ────────▶      │                               │  ────────▶   │$│ ┌────────────┴─┐
     ::: |    ___||_     _|:::                  │                               │              └─┤ │$            $│
     ::: |   |      |   |  :::                 /│                               │\               │$│              │
      :: |___|      |___|  ::                  /│                               │\               └─┤  `sharesOut` │
       :        ????       :                    │                      \(^o^)/  │                  │$            $│
        `:::::::::::::::::'                     │                     YieldMath │                  └──────────────┘
          `-:::::::::::-'                       └───────────────────────────────┘
    */
    /// Calculates the amount of fyToken a user could sell for given amount of Shares.
    /// @param sharesReserves shares reserves amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param sharesOut Shares amount to be traded
    /// @param timeTillMaturity time till maturity in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64
    /// @param g fee coefficient, multiplied by 2^64
    /// @param c price of shares in terms of Dai, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return fyTokenIn the amount of fyToken a user could sell for given amount of Shares
    function fyTokenInForSharesOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 sharesOut,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

                y = fyToken reserves
                z = shares reserves
                x = Δz (sharesOut)

                     (                  sum                                )^(   invA    ) - y
                     (    Za          ) + (  Ya  ) - (       Zxa           )^(   invA    ) - y
                Δy = ( c/μ * (μz)^(1-t) +  y^(1-t) - c/μ * (μz - μx)^(1-t) )^(1 / (1 - t)) - y

            */

        unchecked {
            require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");

            uint128 a = _computeA(timeTillMaturity, k, g);
            uint256 sum;
            {
                // normalizedSharesReserves = μ * sharesReserves
                uint256 normalizedSharesReserves;
                require((normalizedSharesReserves = mu.mulu(sharesReserves)) <= MAX, "YieldMath: Rate overflow (nsr)");

                // za = c/μ * (normalizedSharesReserves ** a)
                // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
                // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
                uint256 za;
                require(
                    (za = c.div(mu).mulu(uint128(normalizedSharesReserves).pow(a, ONE))) <= MAX,
                    "YieldMath: Rate overflow (za)"
                );

                // ya = fyTokenReserves ** a
                // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
                // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
                uint256 ya = fyTokenReserves.pow(a, ONE);

                // normalizedSharesOut = μ * sharesOut
                uint256 normalizedSharesOut;
                require((normalizedSharesOut = mu.mulu(sharesOut)) <= MAX, "YieldMath: Rate overflow (nso)");

                // zx = normalizedSharesReserves + sharesOut * μ
                require(normalizedSharesReserves >= normalizedSharesOut, "YieldMath: Too many shares in");
                uint256 zx = normalizedSharesReserves - normalizedSharesOut;

                // zxa = c/μ * zx ** a
                // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
                // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
                uint256 zxa = c.div(mu).mulu(uint128(zx).pow(a, ONE));

                // sum = za + ya - zxa
                // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
                require((sum = za + ya - zxa) <= MAX, "YieldMath: > fyToken reserves");
            }

            // result = fyTokenReserves - (sum ** (1/a))
            // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
            // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
            uint256 result;
            require(
                (result = uint256(uint128(sum).pow(ONE, a)) - uint256(fyTokenReserves)) <= MAX,
                "YieldMath: Rounding error"
            );

            return uint128(result);
        }
    }

    /* ----------------------------------------------------------------------------------------------------------------
                                              ┌───────────────────────────────┐                    .-:::::::::::-.
      ┌──────────────┐                        │                               │                  .:::::::::::::::::.
      │$            $│                       \│                               │/                :  _______  __   __ :
      │ ┌────────────┴─┐                     \│                               │/               :: |       ||  | |  |::
      │ │$            $│                      │    sharesInForFYTokenOut      │               ::: |    ___||  |_|  |:::
      │$│ ┌────────────┴─┐     ────────▶      │                               │  ────────▶    ::: |   |___ |       |:::
      └─┤ │$            $│                    │                               │               ::: |    ___||_     _|:::
        │$│    SHARES    │                   /│                               │\              ::: |   |      |   |  :::
        └─┤     ????     │                   /│                               │\               :: |___|      |___|  ::
          │$            $│                    │                      \(^o^)/  │                 :   `fyTokenOut`    :
          └──────────────┘                    │                     YieldMath │                  `:::::::::::::::::'
                                              └───────────────────────────────┘                    `-:::::::::::-'
    */
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param fyTokenOut fyToken amount to be traded
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
    /// @param g fee coefficient, multiplied by 2^64 -- sb under 1.0 for selling shares to pool
    /// @param c price of shares in terms of their base, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- starts as c at initialization
    /// @return result the amount of shares a user would have to pay for given amount of fyToken
    function sharesInForFYTokenOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenOut,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128) {
        unchecked {
            require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");
            return
                _sharesInForFYTokenOut(
                    sharesReserves,
                    fyTokenReserves,
                    fyTokenOut,
                    _computeA(timeTillMaturity, k, g),
                    c,
                    mu
                );
        }
    }

    /// @dev Splitting sharesInForFYTokenOut in two functions to avoid stack depth limits
    function _sharesInForFYTokenOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 fyTokenOut,
        uint128 a,
        int128 c,
        int128 mu
    ) private pure returns (uint128) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

        y = fyToken reserves
        z = shares reserves
        x = Δy (fyTokenOut)

             1/μ * (                 subtotal                            )^(   invA    ) - z
             1/μ * ((     Za       ) + (  Ya  ) - (    Yxa    )) / (c/μ) )^(   invA    ) - z
        Δz = 1/μ * (( c/μ * μz^(1-t) +  y^(1-t) - (y - x)^(1-t)) / (c/μ) )^(1 / (1 - t)) - z

        */
        unchecked {
            // normalizedSharesReserves = μ * sharesReserves
            require(mu.mulu(sharesReserves) <= MAX, "YieldMath: Rate overflow (nsr)");

            // za = c/μ * (normalizedSharesReserves ** a)
            // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
            // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
            uint256 za = c.div(mu).mulu(uint128(mu.mulu(sharesReserves)).pow(a, ONE));
            require(za <= MAX, "YieldMath: Rate overflow (za)");

            // ya = fyTokenReserves ** a
            // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
            // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
            uint256 ya = fyTokenReserves.pow(a, ONE);

            // yxa = (fyTokenReserves - x) ** aß
            // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
            // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
            uint256 yxa = (fyTokenReserves - fyTokenOut).pow(a, ONE);
            require(fyTokenOut <= fyTokenReserves, "YieldMath: Underflow (yxa)");

            uint256 zaYaYxa;
            require((zaYaYxa = (za + ya - yxa)) <= MAX, "YieldMath: Rate overflow (zyy)");

            int128 subtotal = int128(ONE).div(mu).mul(
                (uint128(zaYaYxa.divu(uint128(c.div(mu)))).pow(uint128(ONE), uint128(a))).i128()
            );

            // subtotal is calculated as a positive fraction multiplied by a uint so it cannot underflow when casting to uint and its ok to use a raw casting
            uint128 sharesOut = uint128(subtotal) - sharesReserves;
            require(sharesOut <= uint128(subtotal), "YieldMath: Underflow error");
            return sharesOut;
        }
    }

    /// Calculates the max amount of fyToken a user could sell.
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
    /// @param g fee coefficient, multiplied by 2^64 -- sb over 1.0 for buying shares from the pool
    /// @param c price of shares in terms of their base, multiplied by 2^64
    /// @return fyTokenIn the max amount of fyToken a user could sell
    function maxFYTokenIn(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128 fyTokenIn) {
        /* https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/

                Y = fyToken reserves
                Z = shares reserves
                y = maxFYTokenIn

                     (                  sum        )^(   invA    ) - Y
                     (    Za          ) + (  Ya  ) )^(   invA    ) - Y
                Δy = ( c/μ * (μz)^(1-t) +  Y^(1-t) )^(1 / (1 - t)) - Y

            */

        unchecked {
            require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");

            uint128 a = _computeA(timeTillMaturity, k, g);
            uint256 sum;
            {
                // normalizedSharesReserves = μ * sharesReserves
                uint256 normalizedSharesReserves;
                require((normalizedSharesReserves = mu.mulu(sharesReserves)) <= MAX, "YieldMath: Rate overflow (nsr)");

                // za = c/μ * (normalizedSharesReserves ** a)
                // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
                // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
                uint256 za;
                require(
                    (za = c.div(mu).mulu(uint128(normalizedSharesReserves).pow(a, ONE))) <= MAX,
                    "YieldMath: Rate overflow (za)"
                );

                // ya = fyTokenReserves ** a
                // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
                // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
                uint256 ya = fyTokenReserves.pow(a, ONE);

                // sum = za + ya
                // z < MAX, y < MAX, a < 1. It can only underflow, not overflow.
                require((sum = za + ya) <= MAX, "YieldMath: > fyToken reserves");
            }

            // result = (sum ** (1/a)) - fyTokenReserves
            // The “pow(x, y, z)” function not only calculates x^(y/z) but also normalizes the result to
            // fit into 64.64 fixed point number, i.e. it actually calculates: x^(y/z) * (2^63)^(1 - y/z)
            uint256 result;
            require(
                (result = uint256(uint128(sum).pow(ONE, a)) - uint256(fyTokenReserves)) <= MAX,
                "YieldMath: Rounding error"
            );

            fyTokenIn = uint128(result);
        }
    }

    /// Calculates the max amount of fyToken a user could get.
    /// https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
    /// @param g fee coefficient, multiplied by 2^64 -- sb under 1.0 for selling shares to pool
    /// @param c price of shares in terms of their base, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- c at initialization
    /// @return fyTokenOut the max amount of fyToken a user could get
    function maxFYTokenOut(
        uint128 sharesReserves,
        uint128 fyTokenReserves,
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128 fyTokenOut) {
        unchecked {
            require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");

            int128 a = int128(_computeA(timeTillMaturity, k, g));

            /*
                y = maxFyTokenOut
                Y = fyTokenReserves (virtual)
                Z = sharesReserves

                    Y - ( (       numerator           ) / (  denominator  ) )^invA
                    Y - ( ( (    Za      ) + (  Ya  ) ) / (  denominator  ) )^invA
                y = Y - ( (   c/μ * (μZ)^a +    Y^a   ) / (    c/μ + 1    ) )^(1/a)
            */

            // za = c/μ * ((μ * (sharesReserves / 1e18)) ** a)
            int128 za = c.div(mu).mul(mu.mul(sharesReserves.divu(WAD)).pow(a));

            // ya = (fyTokenReserves / 1e18) ** a
            int128 ya = fyTokenReserves.divu(WAD).pow(a);

            // numerator = za + ya
            int128 numerator = za.add(ya);

            // denominator = c/u + 1
            int128 denominator = c.div(mu).add(int128(ONE));

            // rightTerm = (numerator / denominator) ** (1/a)
            int128 rightTerm = numerator.div(denominator).pow(int128(ONE).div(a));

            // maxFYTokenOut_ = fyTokenReserves - (rightTerm * 1e18)
            require((fyTokenOut = fyTokenReserves - uint128(rightTerm.mulu(WAD))) <= MAX, "YieldMath: Underflow error");
            require(fyTokenOut <= fyTokenReserves, "YieldMath: Underflow error");
        }
    }

    /// Calculates the max amount of base a user could sell.
    /// https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
    /// @param g fee coefficient, multiplied by 2^64 -- sb under 1.0 for selling shares to pool
    /// @param c price of shares in terms of their base, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- c at initialization
    /// @return sharesIn Calculates the max amount of base a user could sell.
    function maxSharesIn(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // x
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128 sharesIn) {
        unchecked {
            require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");

            int128 a = int128(_computeA(timeTillMaturity, k, g));

            /*
                y = maxSharesIn_
                Y = fyTokenReserves (virtual)
                Z = sharesReserves

                    1/μ ( (       numerator           ) / (  denominator  ) )^invA  - Z
                    1/μ ( ( (    Za      ) + (  Ya  ) ) / (  denominator  ) )^invA  - Z
                y = 1/μ ( ( c/μ * (μZ)^a   +    Y^a   ) / (     c/u + 1   ) )^(1/a) - Z
            */

            // za = c/μ * ((μ * (sharesReserves / 1e18)) ** a)
            int128 za = c.div(mu).mul(mu.mul(sharesReserves.divu(WAD)).pow(a));

            // ya = (fyTokenReserves / 1e18) ** a
            int128 ya = fyTokenReserves.divu(WAD).pow(a);

            // numerator = za + ya
            int128 numerator = za.add(ya);

            // denominator = c/u + 1
            int128 denominator = c.div(mu).add(int128(ONE));

            // leftTerm = 1/μ * (numerator / denominator) ** (1/a)
            int128 leftTerm = int128(ONE).div(mu).mul(numerator.div(denominator).pow(int128(ONE).div(a)));

            // maxSharesIn_ = (leftTerm * 1e18) - sharesReserves
            require((sharesIn = uint128(leftTerm.mulu(WAD)) - sharesReserves) <= MAX, "YieldMath: Underflow error");
            require(sharesIn <= uint128(leftTerm.mulu(WAD)), "YieldMath: Underflow error");
        }
    }

    /*
    This function is not needed as it's return value is driven directly by the shares liquidity of the pool

    https://hackmd.io/lRZ4mgdrRgOpxZQXqKYlFw?view#MaxSharesOut

    function maxSharesOut(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // x
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128 maxSharesOut_) {} */

    /// Calculates the total supply invariant.
    /// https://docs.google.com/spreadsheets/d/14K_McZhlgSXQfi6nFGwDvDh4BmOu6_Hczi_sFreFfOE/
    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param totalSupply total supply
    /// @param timeTillMaturity time till maturity in seconds e.g. 90 days in seconds
    /// @param k time till maturity coefficient, multiplied by 2^64.  e.g. 25 years in seconds
    /// @param g fee coefficient, multiplied by 2^64 -- use under 1.0 (g2)
    /// @param c price of shares in terms of their base, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- c at initialization
    /// @return result Calculates the total supply invariant.
    function invariant(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // x
        uint256 totalSupply, // s
        uint128 timeTillMaturity,
        int128 k,
        int128 g,
        int128 c,
        int128 mu
    ) public pure returns (uint128 result) {
        if (totalSupply == 0) return 0;
        int128 a = int128(_computeA(timeTillMaturity, k, g));

        result = _invariant(sharesReserves, fyTokenReserves, totalSupply, a, c, mu);
    }

    /// @param sharesReserves yield bearing vault shares reserve amount
    /// @param fyTokenReserves fyToken reserves amount
    /// @param totalSupply total supply
    /// @param a 1 - g * t computed
    /// @param c price of shares in terms of their base, multiplied by 2^64
    /// @param mu (μ) Normalization factor -- c at initialization
    /// @return result Calculates the total supply invariant.
    function _invariant(
        uint128 sharesReserves, // z
        uint128 fyTokenReserves, // x
        uint256 totalSupply, // s
        int128 a,
        int128 c,
        int128 mu
    ) internal pure returns (uint128 result) {
        unchecked {
            require(c > 0 && mu > 0, "YieldMath: c and mu must be positive");

            /*
                y = invariant
                Y = fyTokenReserves (virtual)
                Z = sharesReserves
                s = total supply

                    c/μ ( (       numerator           ) / (  denominator  ) )^invA  / s 
                    c/μ ( ( (    Za      ) + (  Ya  ) ) / (  denominator  ) )^invA  / s 
                y = c/μ ( ( c/μ * (μZ)^a   +    Y^a   ) / (     c/u + 1   ) )^(1/a) / s
            */

            // za = c/μ * ((μ * (sharesReserves / 1e18)) ** a)
            int128 za = c.div(mu).mul(mu.mul(sharesReserves.divu(WAD)).pow(a));

            // ya = (fyTokenReserves / 1e18) ** a
            int128 ya = fyTokenReserves.divu(WAD).pow(a);

            // numerator = za + ya
            int128 numerator = za.add(ya);

            // denominator = c/u + 1
            int128 denominator = c.div(mu).add(int128(ONE));

            // topTerm = c/μ * (numerator / denominator) ** (1/a)
            int128 topTerm = c.div(mu).mul((numerator.div(denominator)).pow(int128(ONE).div(a)));

            result = uint128((topTerm.mulu(WAD) * WAD) / totalSupply);
        }
    }

    /* UTILITY FUNCTIONS
     ******************************************************************************************************************/

    function _computeA(
        uint128 timeTillMaturity,
        int128 k,
        int128 g
    ) private pure returns (uint128) {
        // t = k * timeTillMaturity
        int128 t = k.mul(timeTillMaturity.fromUInt());
        require(t >= 0, "YieldMath: t must be positive"); // Meaning neither T or k can be negative

        // a = (1 - gt)
        int128 a = int128(ONE).sub(g.mul(t));
        require(a > 0, "YieldMath: Too far from maturity");
        require(a <= int128(ONE), "YieldMath: g must be positive");

        return uint128(a);
    }
}
