// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import "@yield-protocol/utils-v2/contracts/access/Ownable.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/ERC20.sol";
import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "@yield-protocol/yieldspace-interfaces/IPoolFactory.sol";
import "./ERC20Mock.sol";


library RMath { // Fixed point arithmetic in Ray units
    /// @dev Multiply an amount by a fixed point factor in ray units, returning an amount
    function rmul(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            uint256 _z = uint256(x) * uint256(y) / 1e27;
            require (_z <= type(uint128).max, "RMUL Overflow");
            z = uint128(_z);
        }
    }

    /// @dev Divide x and y, with y being fixed point. If both are integers, the result is a fixed point factor. Rounds down.
    function rdiv(uint128 x, uint128 y) internal pure returns (uint128 z) {
        unchecked {
            require (y > 0, "RDIV by zero");
            uint256 _z = uint256(x) * 1e27 / y;
            require (_z <= type(uint128).max, "RDIV Overflow");
            z = uint128(_z);
        }
    }
}

contract PoolMock is ERC20, Ownable() {
    using RMath for uint128;

    event Trade(uint32 maturity, address indexed from, address indexed to, int256 baseAmount, int256 fyTokenAmount);
    event Liquidity(uint32 maturity, address indexed from, address indexed to, address fyTokenTo, int256 baseAmount, int256 fyTokenAmount, int256 poolTokenAmount);

    IERC20 public base;
    IFYToken public fyToken;
    uint128 constant public rate = 105e25; // 5%

    uint112 public baseReserves;
    uint112 public fyTokenReserves;

    constructor() ERC20("Pool", "Pool", 18) {
        fyToken = IFYToken(IPoolFactory(msg.sender).nextFYToken());
        base = IERC20(IPoolFactory(msg.sender).nextBase());
    }

    function sync() public {
        (baseReserves, fyTokenReserves) = (uint112(base.balanceOf(address(this))), uint112(fyToken.balanceOf(address(this))));
    }

    function update(uint112 baseReserves_, uint112 fyTokenReserves_) public {
        baseReserves = baseReserves_;
        fyTokenReserves = fyTokenReserves_;
    }

    function getBaseReserves() public view returns(uint128) {
        return uint128(base.balanceOf(address(this)));
    }

    function getFYTokenReserves() public view returns(uint128) {
        return uint128(fyToken.balanceOf(address(this)));
    }

    function retrieveBase(address to)
        external
        returns(uint128 surplus)
    {
        surplus = getBaseReserves() - baseReserves;
        require(
            base.transfer(to, surplus),
            "Pool: Base transfer failed"
        );
    }

    function retrieveFYToken(address to)
        external payable
        returns(uint128 surplus)
    {
        surplus = getFYTokenReserves() - fyTokenReserves;
        require(
            fyToken.transfer(to, surplus),
            "Pool: FYToken transfer failed"
        );
    }

    function mint(address to, bool, uint256 minTokensMinted)
        external
        returns (uint256 baseIn, uint256 fyTokenIn, uint256 tokensMinted) {
        baseIn = uint128(base.balanceOf(address(this))) - baseReserves;
        if (_totalSupply > 0) {
            tokensMinted = (_totalSupply * baseIn) / baseReserves;
            fyTokenIn = (fyTokenReserves * tokensMinted) / _totalSupply;
        } else {
            tokensMinted = baseIn;
        }
        require(fyTokenReserves + fyTokenIn <= fyToken.balanceOf(address(this)), "Pool: Not enough fyToken in");
        require (tokensMinted >= minTokensMinted, "Pool: Not enough tokens minted");

        (baseReserves, fyTokenReserves) = (baseReserves + uint112(baseIn), fyTokenReserves + uint112(fyTokenIn));
        
        _mint(to, tokensMinted);

        emit Liquidity(0, msg.sender, to, address(0), -int256(baseIn), -int256(fyTokenIn), int256(tokensMinted));
    }

    function burn(address baseTo, address fyTokenTo, uint256 minBaseOut, uint256 minFYTokenOut)
        external
        returns (uint256 tokensBurned, uint256 baseOut, uint256 fyTokenOut) {
        tokensBurned = _balanceOf[address(this)];

        baseOut = (tokensBurned * baseReserves) / _totalSupply;
        fyTokenOut = (tokensBurned * fyTokenReserves) / _totalSupply;

        require (baseOut >= minBaseOut, "Pool: Not enough base tokens obtained");
        require (fyTokenOut >= minFYTokenOut, "Pool: Not enough fyToken obtained");

        (baseReserves, fyTokenReserves) = (baseReserves - uint112(baseOut), fyTokenReserves - uint112(fyTokenOut));

        _burn(address(this), tokensBurned);
        base.transfer(baseTo, baseOut);
        fyToken.transfer(fyTokenTo, fyTokenOut);

        emit Liquidity(0, msg.sender, baseTo, fyTokenTo, int256(baseOut), int256(fyTokenOut), -int(tokensBurned));
    }


    function sellBasePreview(uint128 baseIn) public pure returns(uint128) {
        return baseIn.rmul(rate);
    }

    function buyBasePreview(uint128 baseOut) public pure returns(uint128) {
        return baseOut.rmul(rate);
    }

    function sellFYTokenPreview(uint128 fyTokenIn) public pure returns(uint128) {
        return fyTokenIn.rdiv(rate);
    }

    function buyFYTokenPreview(uint128 fyTokenOut) public pure returns(uint128) {
        return fyTokenOut.rdiv(rate);
    }

    function sellBase(address to, uint128 min) external returns(uint128) {
        uint128 baseIn = uint128(base.balanceOf(address(this))) - baseReserves;
        uint128 fyTokenOut = sellBasePreview(baseIn);
        require(fyTokenOut >= min, "Pool: Not enough fyToken obtained");
        fyToken.transfer(to, fyTokenOut);
        (baseReserves, fyTokenReserves) = (uint112(base.balanceOf(address(this))), uint112(fyTokenReserves - fyTokenOut));
        emit Trade(uint32(fyToken.maturity()), msg.sender, to, int128(baseIn), -int128(fyTokenOut));
        return fyTokenOut;
    }

    function buyBase(address to, uint128 baseOut, uint128 max) external returns(uint128) {
        uint128 fyTokenIn = buyBasePreview(baseOut);
        require(fyTokenIn <= max, "Pool: Too much fyToken in");
        require(fyTokenReserves + fyTokenIn <= getFYTokenReserves(), "Pool: Not enough fyToken in");
        base.transfer(to, baseOut);
        (baseReserves, fyTokenReserves) = (uint112(baseReserves - baseOut), uint112(fyTokenReserves + fyTokenIn));
        emit Trade(uint32(fyToken.maturity()), msg.sender, to, -int128(baseOut), int128(fyTokenIn));
        return fyTokenIn;
    }

    function sellFYToken(address to, uint128 min) external returns(uint128) {
        uint128 fyTokenIn = uint128(fyToken.balanceOf(address(this))) - fyTokenReserves;
        uint128 baseOut = sellFYTokenPreview(fyTokenIn);
        require(baseOut >= min, "Pool: Not enough base obtained");
        base.transfer(to, baseOut);
        (baseReserves, fyTokenReserves) = (uint112(baseReserves - baseOut), uint112(fyToken.balanceOf(address(this))));
        emit Trade(uint32(fyToken.maturity()), msg.sender, to, -int128(baseOut), int128(fyTokenIn));
        return baseOut;
    }

    function buyFYToken(address to, uint128 fyTokenOut, uint128 max) external returns(uint128) {
        uint128 baseIn = buyFYTokenPreview(fyTokenOut);
        require(baseIn <= max, "Pool: Too much base token in");
        require(baseReserves + baseIn <= getBaseReserves(), "Pool: Not enough base token in");
        fyToken.transfer(to, fyTokenOut);
        (baseReserves, fyTokenReserves) = (uint112(baseReserves + baseIn), uint112(fyTokenReserves - fyTokenOut));
        emit Trade(uint32(fyToken.maturity()), msg.sender, to, int128(baseIn), -int128(fyTokenOut));
        return baseIn;
    }
}
