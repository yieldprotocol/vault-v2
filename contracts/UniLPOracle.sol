pragma solidity ^0.6.2;
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./interfaces/IUniswap.sol";
import "./interfaces/IOracle.sol";
import "./Constants.sol";

import "@nomiclabs/buidler/console.sol";


contract UniLPOracle is IOracle, Constants {
    using SafeMath for uint256;
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    IUniswap internal _uniswap;

    constructor (address uniswap_) public {
        _uniswap = IUniswap(uniswap_);
    }

    function price() public override returns(uint256) {
        (uint112 _reserve0, uint112 _reserve1,) = _uniswap.getReserves();
        uint256 _totalSupply = _uniswap.totalSupply();
        uint256 _r0 = uint256(_reserve0);
        uint256 _r1 = uint256(_reserve1);
        return 2 * sqrt(_r0.mul(_r1))
            .divd(_totalSupply, WAD)
            .muld(RAY.unit(), WAD);           //converty to RAY
    }

    // We should replace this sqrt with the appropriate library version, if any
    function sqrt(uint x) private pure returns (uint y) {
        uint z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}