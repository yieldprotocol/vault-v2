// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;

import "./IPoolOracle.sol";
import "@yield-protocol/yieldspace-interfaces/IPool.sol";
import "@yield-protocol/vault-interfaces/src/IOracle.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "@yield-protocol/yieldspace-v2/contracts/YieldMath.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/math/WDiv.sol";

contract YieldSpaceMultiOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;
    using Math64x64 for int128;
    using Math64x64 for uint128;
    using Math64x64 for int256;
    using Math64x64 for uint256;
    using Exp64x64 for uint128;
    using WMul for uint256;
    using WDiv for uint256;

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
        int128 ts;
        int128 g;
    }

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    IPoolOracle public immutable poolOracle;
    int128 public immutable wad64x64;

    constructor(IPoolOracle _poolOracle) {
        poolOracle = _poolOracle;
        wad64x64 = uint256(1e18).fromUInt();
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

        sources[seriesId][baseId] = Source(pool, maturity, false, ts, g2);
        emit SourceSet(seriesId, baseId, pool, maturity, ts, g2);

        sources[baseId][seriesId] = Source(pool, maturity, true, ts, g1);
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

        if (source.maturity > updateTime) {
            value = _discount(source, amount, uint128(poolOracle.peek(source.pool)), updateTime);
        } else {
            value = amount;
        }
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

        if (source.maturity > updateTime) {
            value = _discount(source, amount, uint128(poolOracle.get(source.pool)), updateTime);
        } else {
            value = amount;
        }
    }

    function _source(bytes32 base, bytes32 quote) internal view returns (Source memory source) {
        source = sources[base.b6()][quote.b6()];
        require(source.pool != address(0), "Source not found");
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
        uint128 unitPrice,
        uint256 updateTime
    ) internal view returns (uint256) {
        int128 timeTillMaturity = uint128(source.maturity - updateTime).fromUInt();
        int128 powerValue64 = source.g.mul(source.ts).mul(timeTillMaturity);
        // scale to 18 dec and convert to regular non-64
        uint128 powerValue = uint128(powerValue64.mul(wad64x64).toUInt());

        uint256 top = unitPrice.pow(powerValue, uint128(1e18));
        uint256 bottom = uint128(1e18).pow(powerValue, uint128(1e18)) / 1e18;
        uint256 marginalPrice = top / bottom;

        return source.lending ? amount.wmul(marginalPrice) : amount.wdiv(marginalPrice);
    }
}
