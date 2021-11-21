// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import "@yield-protocol/vault-interfaces/IOracle.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastBytes32Bytes6.sol";
import "./ICurvePool.sol";
import "../chainlink/AggregatorV3Interface.sol";

// Oracle Code Inspiration: https://github.com/Abracadabra-money/magic-internet-money/blob/main/contracts/oracles/3CrvOracle.sol
contract DummyConvexCurveOracle  is IOracle{
    using CastBytes32Bytes6 for bytes32;
    ICurvePool immutable public threecrv;
    AggregatorV3Interface immutable public DAI;
    AggregatorV3Interface immutable public USDC;
    AggregatorV3Interface immutable public USDT;

    bytes32 public immutable cvx3CrvId;
    bytes32 public immutable ethId;
    
    constructor(bytes32 cvx3CrvId_, bytes32 ethId_,ICurvePool threecrv_, AggregatorV3Interface DAI_, AggregatorV3Interface USDC_, AggregatorV3Interface USDT_) {
        cvx3CrvId = cvx3CrvId_;
        ethId = ethId_;
        threecrv = threecrv_;
        DAI = DAI_;
        USDC = USDC_;
        USDT = USDT_;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * Only `cvx3crvid` and `ethId` are accepted as asset identifiers.
     */
    function peek(bytes32 base,bytes32 quote,uint256 baseAmount
    ) external view virtual override returns (uint256 quoteAmount, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), baseAmount);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price. Same as `peek` for this oracle.
     * Only `cvx3crvid` and `ethId` are accepted as asset identifiers.
     */
    function get(bytes32 base,bytes32 quote,uint256 baseAmount
    ) external virtual override returns (uint256 quoteAmount, uint256 updateTime) {
        return _peek(base.b6(), quote.b6(), baseAmount);
    }

    /**
     * @notice Retrieve the value of the amount at the latest oracle price.
     * Only `cvx3crvid` and `ethId` are accepted as asset identifiers.
     */
    function _peek(bytes6 base,bytes6 quote,uint256 baseAmount
    ) private view returns (uint256 quoteAmount, uint256 updateTime) {
        (,int daiPrice,,,) =DAI.latestRoundData();
        (,int usdcPrice,,,) =USDC.latestRoundData();
        (,int usdtPrice,,,) =USDT.latestRoundData();
        uint256 minStable = min(uint(daiPrice), min(uint(usdcPrice), uint(usdtPrice)));
        
        uint price  = (threecrv.get_virtual_price()*minStable)/1e18;
        
        if(base==cvx3CrvId&&(quote==ethId)){
            quoteAmount = baseAmount * price/(1e18);
        } if(quote==cvx3CrvId&&(base==ethId)){
            quoteAmount = baseAmount * (1e18)/price;
        }
        updateTime = block.timestamp;
    }
}
