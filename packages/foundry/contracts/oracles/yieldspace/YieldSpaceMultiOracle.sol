// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/yieldspace-tv/src/interfaces/IPool.sol";
import "@yield-protocol/yieldspace-tv/src/interfaces/IPoolOracle.sol";
import "@yield-protocol/yieldspace-tv/src/YieldMath.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/math/WDiv.sol";
import "../../interfaces/IOracle.sol";

contract YieldSpaceMultiOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;
    using CastU256U128 for uint256;
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;
    using WMul for uint256;
    using WDiv for uint256;

    error SourceNotFound(bytes32 baseId, bytes32 quoteId);

    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed quoteId,
        address indexed pool,
        uint32 maturity,
        int128 ts,
        int128 g
    );

    struct Source {
        address pool;
        uint32 maturity;
        bool lending;
        int128 gts;
    }

    uint128 public constant ONE = 1e18;

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    IPoolOracle public immutable poolOracle;

    constructor(IPoolOracle _poolOracle) {
        poolOracle = _poolOracle;
    }

    /// @notice Set or reset a FYToken oracle source and its inverse
    /// @param  seriesId FYToken id
    /// @param  baseId Underlying id
    /// @param  pool Pool where you can trade FYToken <-> underlying
    /// @dev    parameter ORDER IS crucial!  If id's are out of order the math will be wrong
    function setSource(
        bytes6 seriesId,
        bytes6 baseId,
        address pool
    ) external auth {
        // Cache pool immutable values to save gas when discounting the amounts
        uint32 maturity = IPool(pool).maturity();
        int128 ts = IPool(pool).ts();
        int128 g1 = IPool(pool).g1();
        int128 g2 = IPool(pool).g2();

        // Initialise or update the TWAR observations
        poolOracle.update(pool);

        sources[seriesId][baseId] = Source(pool, maturity, false, ts.mul(g2));
        emit SourceSet(seriesId, baseId, pool, maturity, ts, g2);

        sources[baseId][seriesId] = Source(pool, maturity, true, ts.mul(g1));
        emit SourceSet(baseId, seriesId, pool, maturity, ts, g1);
    }

    /// @inheritdoc IOracle
    function peek(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external view override returns (uint256 value, uint256 updateTime) {
        //solhint-disable-next-line not-rely-on-time
        updateTime = block.timestamp;

        if (base == quote) return (amount, updateTime);

        Source memory source = _source(base, quote);

        value = source.maturity > updateTime
            ? _discount(
                source,
                amount,
                poolOracle.peek(source.pool),
                updateTime
            )
            : amount;
    }

    /// @inheritdoc IOracle
    function get(
        bytes32 base,
        bytes32 quote,
        uint256 amount
    ) external override returns (uint256 value, uint256 updateTime) {
        //solhint-disable-next-line not-rely-on-time
        updateTime = block.timestamp;

        if (base == quote) return (amount, updateTime);

        Source memory source = _source(base, quote);

        value = source.maturity > updateTime
            ? _discount(source, amount, poolOracle.get(source.pool), updateTime)
            : amount;
    }

    /// @dev Load a source for the base/quote and verify is valid
    /// @param base The asset in which the amount to be converted is represented
    /// @param quote The asset in which the converted value will be represented
    function _source(bytes32 base, bytes32 quote)
        internal
        view
        returns (Source memory source)
    {
        source = sources[base.b6()][quote.b6()];

        if (source.pool == address(0)) {
            revert SourceNotFound(base, quote);
        }
    }

    /// @dev Discount `amount` using the TWAR oracle rates.
    /// Lending => underlying to FYToken. Borrowing => FYToken to underlying
    /// @param source Input params for the formulae
    /// @param amount Amount to be discounted
    /// @param unitPrice TWAR provided by the oracle
    /// @param updateTime Time when the TWAR observation was calculated
    /// @return the discounted amount, <= `amount` when borrowing, >= `amount` when lending
    function _discount(
        Source memory source,
        uint256 amount,
        uint256 unitPrice,
        uint256 updateTime
    ) internal pure returns (uint256) {
        int128 timeTillMaturity = (source.maturity - updateTime).fromUInt();

        uint128 powerValue = source.gts.mul(timeTillMaturity).mulu(ONE).u128();

        uint256 top = (unitPrice).u128().pow(powerValue, ONE);
        uint256 bottom = ONE.pow(powerValue, ONE) / ONE;
        uint256 marginalPrice = top / bottom;

        return
            source.lending
                ? amount.wmul(marginalPrice)
                : amount.wdiv(marginalPrice);
    }
}
