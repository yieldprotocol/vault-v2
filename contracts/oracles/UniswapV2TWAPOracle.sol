// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import "@yield-protocol/vault-interfaces/IOracle.sol";
import "./IUniswapV2Pair.sol";


contract UniswapV2TWAPOracle is IOracle {
    /**
     * UNISWAP_MIN_TWAP_PERIOD plays two roles:
     *
     * 1. Minimum age of the stored CumulativePrice we calculate our current TWAP vs.  Eg, if one of our stored prices is from
     * 5 secs ago, and the other from 10 min ago, we should calculate TWAP vs the 10-min-old one, since a 5-second TWAP is too
     * short - relatively easy to manipulate.
     *
     * 2. Minimum time gap between stored CumulativePrices.  Eg, if we stored one 5 seconds ago, we don't need to store another
     * one now - and shouldn't, since then if someone else made a TWAP call a few seconds later, both stored prices would be
     * too recent to calculate a robust TWAP.
     *
     * These roles could in principle be separated, eg: "Require the stored price we calculate TWAP from to be >= 2 minutes
     * old, but leave >= 10 minutes before storing a new price."  But for simplicity we manage both with one constant.
     */
    uint public constant UNISWAP_MIN_TWAP_PERIOD = 10 minutes;

    uint public constant WAD = 1e18;
    uint public constant BILLION = 1e9;
    uint public constant HALF_BILLION = BILLION / 2;
    // Uniswap stores its cumulative prices in "FixedPoint.uq112x112" format - 112-bit fixed point:
    uint public constant UNISWAP_CUM_PRICE_SCALE_FACTOR = 2 ** 112;

    IUniswapV2Pair public immutable uniswapPair;
    uint public immutable uniswapTokenToUse;        // 0 -> calc TWAP from stored token0, 1 -> token1.  We only use one of them
    /**
     * Uniswap pairs store cumPriceSeconds: let's suppose the intended cumulative price-seconds stored is 12.345.  Converting
     * from the stored format to our standard WAD format (18 decimal places, eg 12.345 * 1e18) involves several steps:
     *
     * 1. Uniswap stores the values in 112-bit fixed-point format.  So instead of 12.345, the pair stores 12.345 * 2**112 =
     *    6.41e34.
     * 2. ...Except, Uniswap's values are additional shifted by a certain number of decimal places.  Eg, USDC/ETH stores
     *    token1, the cumulative ETH price in USDC terms, shifted down (divided) by 12 decimal places: so 12.345 is stored as
     *    12.345 * 2**112 / 1e12 = 6.41 * 1e22.  (See the constructor's tokenDecimals argument below.)
     * 3. To get our desired 1e18 scaling, we need to divide that stored number, 12.345 * 2**112 / 1e12, by 2**112 / 1e30 =
     *    5,129.2969.
     * 4. However, because we're storing uniswapScaleFactor as a uint, we need to scale it up: 5129 alone would lose too much
     *    precision (and if Uniswap's value is shifted by >12 decimal places, uniswapScaleFactor can even end up < 1).  So we
     *    WAD-scale uniswapScaleFactor, setting it in the example to not 2**112 / 1e30, but (2**112 / 1e30) * 1e18 =
     *    5192296858534827628530.
     *
     * So when we get a raw value from Uniswap like 12.345 * 2**112 / 1e12 = 6.41 * 1e22, we multiply it by WAD (getting
     * 6.41e40), and divide by uniswapScaleFactor = 5192296858534827628530, yielding the desired 12.345 * 1e18.
     */
    uint public immutable uniswapScaleFactor;

    struct CumulativePrice {
        uint32 cumPriceSecondsTime;
        uint144 cumPriceSeconds;    // In billionths.  See cumulativePriceFromPair() below for explanation of "cumPriceSeconds"
        uint80 price;               // In billionths.  Just the latest output TWAP price recorded
    }

    event TWAPPriceSecondsStored(uint cumPriceSecondsTime, uint cumPriceSeconds, uint price);
    event TWAPPriceUpdated(uint price);

    /**
     * We store two CumulativePrices, A and B, without specifying which is more recent.  This is so that we only need to do one
     * SSTORE each time we save a new one: we can inspect them later to figure out which is newer - see orderedStoredPrices().
     */
    CumulativePrice public uniswapStoredPriceA;
    CumulativePrice public uniswapStoredPriceB;

    /**
     * Example pairs to pass in:
     * ETH/USDT: 0x0d4a11d5eeaac28ec3f61d100daf4d40471f1852, 0, -12
     * USDC/ETH: 0xb4e16d0168e52d35cacd2c6185b44281ec28c9dc, 1, -12
     * DAI/ETH: 0xa478c2975ab1ea89e8196811f51a7b7ade33eb11, 1, 0
     */
    constructor(IUniswapV2Pair pair, uint tokenToUse, int tokenDecimals) {
        uniswapPair = pair;
        require(tokenToUse == 0 || tokenToUse == 1, "tokenToUse not 0 or 1");
        uniswapTokenToUse = tokenToUse;
        uniswapScaleFactor = tokenDecimals >= 0 ?
            UNISWAP_CUM_PRICE_SCALE_FACTOR * 10 ** uint(tokenDecimals) :    // See comment for uniswapScaleFactor above
            UNISWAP_CUM_PRICE_SCALE_FACTOR / 10 ** uint(-tokenDecimals);
    }

    function peek() public virtual override view returns (uint price, uint updateTime) {
        (CumulativePrice storage olderStoredPrice, CumulativePrice storage newerStoredPrice) = orderedStoredPrices();
        // Here we rely on the invariant that after every call to get(), the freshest price is stored on the *newer*
        // of the two storedPrices, but is calculated relative to the timestamp (& cumPriceSeconds) of the *older* storedPrice:
        (price, updateTime) = (newerStoredPrice.price * BILLION, olderStoredPrice.cumPriceSecondsTime);
    }

    /**
     * @notice There's an important distinction here between the two timestamps used here:
     *
     * - `newCumPriceSecondsTime` = the timestamp of the *latest cumulative price-seconds* available from Uniswap.  This is a
     *   real-time value that will (typically) change every time this function is called.
     * - `updateTime` = timestamp of refStoredPrice, the *stored cumulative price-seconds record we calculate TWAP from.*  This
     *   is a value we only store periodically: if this function is called often, it will usually stay unchanged between calls.
     *
     * That is, calculating TWAP requires two cumPriceSeconds values to average between, and these are their timestamps.
     *
     * The most important - potentially confusing - part of this distinction is this: even though the *price* returned will
     * (typically) change every time this function is called, the *`updateTime`* will only change every few minutes, when we
     * update the older of the two cumPriceSeconds in the TWAP.  The principle there is that "the TWAP is only as fresh as the
     * *older* of the two cumPriceSeconds that go into it": if we're calculating a TWAP between one record 5 seconds old and
     * another a day old, it's more accurate to think of that TWAP as "a day old" than "5 seconds fresh".
     */
    function get() public virtual override returns (uint price, uint updateTime) {
        // ("updateTime" here = "refCumPriceSecondsTime": timestamp of the stored cumPriceSeconds we're calculating TWAP vs)

        // 1. Get the Uniswap pair's up-to-date cumulative price-seconds:
        (uint newCumPriceSecondsTime, uint newCumPriceSeconds) = cumulativePriceFromPair();

        // 2. Figure out which of our stored cumPriceSeconds we should be comparing the new one against:
        (CumulativePrice storage olderStoredPrice, CumulativePrice storage newerStoredPrice) = orderedStoredPrices();
        bool isNewerStoredPriceOldEnough = isStoredPriceOldEnoughToCompareVs(newCumPriceSecondsTime, newerStoredPrice);
        CumulativePrice storage refStoredPrice;
        if (isNewerStoredPriceOldEnough) {
            refStoredPrice = newerStoredPrice;
        } else {
            require(isStoredPriceOldEnoughToCompareVs(newCumPriceSecondsTime, olderStoredPrice),
                    "Both stored prices too recent");   // This should never fail unless block time goes backwards...
            refStoredPrice = olderStoredPrice;
        }
        uint refCumPriceSecondsTime = refStoredPrice.cumPriceSecondsTime;

        // 3. Now that we have the new and stored cum prices to compare, subtract-&-divide new vs stored to get the TWAP price:
        price = calculateTWAP(newCumPriceSecondsTime, newCumPriceSeconds, refCumPriceSecondsTime,
                              refStoredPrice.cumPriceSeconds * BILLION);    // Converting stored billionths to WAD format
        updateTime = refCumPriceSecondsTime;

        // 4. Finally, store the latest price (and if changed, the new cumulative price) for use by future calls:
        if (isNewerStoredPriceOldEnough) {
            // Enough time has passed since our newer storedPrice that we're using it as our reference stored price (the one we
            // calculate the TWAP with reference to).  This means we're no longer using the older storedPrice at all, so it's
            // time to replace it:
            storePriceAndCumulativePrice(newCumPriceSecondsTime, newCumPriceSeconds, price, olderStoredPrice);
        } else {
            // We're still using the older storedPrice as our reference price, so we can't replace it yet.  Just update the
            // price (not cumPriceSeconds or cumPriceSecondsTime) of the newer storedPrice:
            storePrice(price, newerStoredPrice);
        }
    }

    /**
     * @notice Store the latest cumPriceSeconds and cumPriceSecondsTime, and the fresh price we calculated with reference to
     * them.
     */
    function storePriceAndCumulativePrice(uint cumPriceSecondsTime, uint cumPriceSeconds, uint price,
                                          CumulativePrice storage storedPriceToReplace)
        internal
    {
        require(cumPriceSecondsTime <= type(uint32).max, "cumPriceSecondsTime overflow");

        uint cumPriceSecondsToStore = cumPriceSeconds + HALF_BILLION;   // cumPriceSeconds is in WAD (1e18), we want 1e9
        unchecked { cumPriceSecondsToStore /= BILLION; }
        require(cumPriceSecondsToStore <= type(uint144).max, "cumPriceSecondsToStore overflow");

        uint priceToStore = price + HALF_BILLION;                       // Again, price is in WAD, divide to get BILLIONs
        unchecked { priceToStore /= BILLION; }
        require(priceToStore <= type(uint80).max, "priceToStore overflow");

        // (Note: this assignment only stores because storedPriceToReplace has modifier "storage" - ie, store by reference!)
        (storedPriceToReplace.cumPriceSecondsTime, storedPriceToReplace.cumPriceSeconds, storedPriceToReplace.price) =
            (uint32(cumPriceSecondsTime), uint144(cumPriceSecondsToStore), uint80(priceToStore));

        emit TWAPPriceSecondsStored(cumPriceSecondsTime, cumPriceSeconds, price);
    }

    /**
     * @notice Store the calculated price (if it's changed).
     */
    function storePrice(uint price, CumulativePrice storage storedPriceToUpdate)
        internal
    {
        uint priceToStore = price + HALF_BILLION;                       // See analogous comment above
        unchecked { priceToStore /= BILLION; }
        if (priceToStore != storedPriceToUpdate.price) {
            require(priceToStore <= type(uint80).max, "priceToStore overflow");
            storedPriceToUpdate.price = uint80(priceToStore);
            emit TWAPPriceUpdated(price);
        }
    }

    function orderedStoredPrices() internal view
        returns (CumulativePrice storage olderStoredPrice, CumulativePrice storage newerStoredPrice)
    {
        (olderStoredPrice, newerStoredPrice) =
            uniswapStoredPriceB.cumPriceSecondsTime > uniswapStoredPriceA.cumPriceSecondsTime ?
            (uniswapStoredPriceA, uniswapStoredPriceB) : (uniswapStoredPriceB, uniswapStoredPriceA);
    }

    function isStoredPriceOldEnoughToCompareVs(uint newCumPriceSecondsTime, CumulativePrice storage storedPrice)
        internal view returns (bool oldEnough)
    {
        // uint32 + x can't overflow:
        unchecked { oldEnough = newCumPriceSecondsTime >= storedPrice.cumPriceSecondsTime + UNISWAP_MIN_TWAP_PERIOD; }
    }

    /**
     * @return timestamp Timestamp at which Uniswap stored the cumPriceSeconds.
     * @return cumPriceSeconds Our pair's cumulative "price-seconds", using Uniswap's TWAP logic.  Eg, if at time t0
     * cumPriceSeconds = 10,000,000 (returned here as 10,000,000 * 1e18, ie, in WAD fixed-point format), and during the 30
     * seconds between t0 and t1 = t0 + 30, the price is $45.67, then at time t1, cumPriceSeconds = 10,000,000 + 30 * 45.67 =
     * 10,001,370.1 (stored as 10,001,370.1 * 1e18).
     */
    function cumulativePriceFromPair()
        public view returns (uint timestamp, uint cumPriceSeconds)
    {
        (,, timestamp) = uniswapPair.getReserves();

        // Retrieve the current Uniswap cumulative price.  Modeled off of Uniswap's own example:
        // https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/examples/ExampleOracleSimple.sol
        uint uniswapCumPrice = uniswapTokenToUse == 1 ?
            uniswapPair.price1CumulativeLast() :
            uniswapPair.price0CumulativeLast();
        cumPriceSeconds = uniswapCumPrice * WAD;
        unchecked { cumPriceSeconds /= uniswapScaleFactor; }
    }

    /**
     * @param newTimestamp in seconds (eg, 1606764888) - not WAD-scaled!
     * @param newCumPriceSeconds WAD-scaled.
     * @param oldTimestamp in raw seconds again.
     * @param oldCumPriceSeconds WAD-scaled.
     * @return price WAD-scaled.
     */
    function calculateTWAP(uint newTimestamp, uint newCumPriceSeconds, uint oldTimestamp, uint oldCumPriceSeconds)
        public pure returns (uint price)
    {
        price = (newCumPriceSeconds - oldCumPriceSeconds) / (newTimestamp - oldTimestamp);
    }
}
