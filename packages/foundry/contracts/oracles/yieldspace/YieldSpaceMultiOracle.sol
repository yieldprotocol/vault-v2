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

import "forge-std/src/Test.sol";

contract YieldSpaceMultiOracle is IOracle, AccessControl {
    using CastBytes32Bytes6 for bytes32;
    using Math64x64 for *;

    error SourceNotFound(bytes32 baseId, bytes32 quoteId);

    event SourceSet(
        bytes6 indexed baseId,
        bytes6 indexed quoteId,
        address indexed pool,
        uint32 maturity,
        int128 ts,
        int128 mu
    );

    struct Source {
        address pool;
        uint32 maturity;
        bool lending;
        int128 ts;
        int128 mu;
    }

    uint128 public constant ONE = 1e18;

    mapping(bytes6 => mapping(bytes6 => Source)) public sources;

    IPoolOracle public immutable poolOracle;

    constructor(IPoolOracle _poolOracle) {
        poolOracle = _poolOracle;
    }

    /// @notice Set or reset a FYToken oracle source and its inverse
    /// @dev    parameter ORDER IS crucial! If the ids are out of order the math will be wrong
    /// @param  seriesId FYToken id
    /// @param  baseId Underlying id
    /// @param  pool Pool where you can trade FYToken <-> underlying
    function setSource(
        bytes6 seriesId,
        bytes6 baseId,
        address pool
    ) external auth {
        // Cache pool immutable values to save gas when discounting the amounts
        uint32 maturity = IPool(pool).maturity();
        int128 ts = IPool(pool).ts();
        int128 mu = IPool(pool).mu();

        // Initialise or update the TWAR observations
        poolOracle.update(pool);

        sources[seriesId][baseId] = Source(pool, maturity, false, ts, mu);
        emit SourceSet(seriesId, baseId, pool, maturity, ts, mu);

        sources[baseId][seriesId] = Source(pool, maturity, true, ts, mu);
        emit SourceSet(baseId, seriesId, pool, maturity, ts, mu);
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

    /// @dev Load the source for the base/quote and verify is valid
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
    /// @param twar TWAR provided by the oracle
    /// @param updateTime Time when the TWAR observation was calculated
    /// @return the discounted amount, <= `amount` when borrowing, >= `amount` when lending
    function _discount(
        Source memory source,
        uint256 amount,
        uint256 twar,
        uint256 updateTime
    ) internal view returns (uint256) {
        /*
            https://hackmd.io/VlQkYJ6cTzWIaIyxuR1g2w
            https://www.desmos.com/calculator/39jpmawgpu
            
            p = (c/μ * twar)^t
            p = (c/μ * twar)^(ts*g*ttm)
        */

        // ttm
        int128 timeTillMaturity = (source.maturity - updateTime).fromUInt();

        int128 c = IPool(source.pool).getC();
        int128 g = source.lending
            ? IPool(source.pool).g2()
            : IPool(source.pool).g1();

        // t = ts * g * ttm
        int128 t = source.ts.mul(g).mul(timeTillMaturity);

        // make twar a binary 64.64 fraction
        int128 twar64 = twar.divu(ONE);

        // p = (c/μ * twar)^t
        int128 p = pow(c.div(source.mu).mul(twar64), t);

        return
            source.lending
                ? p.mulu(amount) // apply discount, result is already a regular unsigned integer
                : amount
                .divu(ONE) // make amount a binary 64.64 fraction
                .div(p).mulu(ONE); // apply discount && make the result a regular unsigned integer
    }

    // TODO move to Exp64x64
    /// @dev x^y = 2^(y*log_2(x))
    function pow(int128 x, int128 y) internal pure returns (int128) {
        return y.mul(x.log_2()).exp_2();
    }
}
