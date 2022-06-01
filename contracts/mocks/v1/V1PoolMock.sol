// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "@yield-protocol/utils-v2/contracts/token/ERC20.sol";
import "../../modules/IV1FYDai.sol";
import "../../modules/IV1Pool.sol";
import "../ERC20Mock.sol";
import "./DelegableMock.sol";


contract V1PoolMock is ERC20, DelegableMock, IV1Pool {

    IERC20 public immutable override dai;
    IV1FYDai public immutable override fyDai;
    uint128 constant public rate = 105e16; // 5%

    constructor(IERC20 dai_, IV1FYDai fyDai_) ERC20("Pool", "Pool", 18) {
        dai = dai_;
        fyDai = fyDai_;
    }

    /// @dev Mint liquidity tokens in exchange for adding dai and fyDai
    /// The liquidity provider needs to have called `dai.approve` and `fyDai.approve`.
    /// @param from Wallet providing the dai and fyDai. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the minted liquidity tokens.
    /// @param daiOffered Amount of `dai` being invested, an appropriate amount of `fyDai` to be invested alongside will be calculated and taken by this function from the caller.
    function mint(address from, address to, uint256 daiOffered)
        external
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns (uint256 tokensMinted)
    {
        uint256 fyDaiRequired;

        if (_totalSupply == 0) {
            tokensMinted = daiOffered;
        } else {
            tokensMinted = daiOffered * _totalSupply / dai.balanceOf(address(this));
            fyDaiRequired = tokensMinted * fyDai.balanceOf(address(this)) / _totalSupply;
            ERC20Mock(address(fyDai)).mint(address(this), fyDaiRequired);
        }
        ERC20Mock(address(dai)).mint(address(this), daiOffered);
        
        _mint(to, tokensMinted);
    }

    /// @dev Burn liquidity tokens in exchange for dai and fyDai.
    /// The liquidity provider needs to have called `pool.approve`.
    /// @param from Wallet providing the liquidity tokens. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the dai and fyDai.
    /// @param tokensBurned Amount of liquidity tokens being burned.
    function burn(address from, address to, uint256 tokensBurned)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns (uint256 daiReturned, uint256 fyDaiReturned)
    {
        daiReturned = tokensBurned * dai.balanceOf(address(this)) / _totalSupply;
        fyDaiReturned = tokensBurned * fyDai.balanceOf(address(this)) / _totalSupply;

        _burn(from, tokensBurned);
        dai.transfer(to, daiReturned);
        fyDai.transfer(to, fyDaiReturned);
    }

    /// @dev Sell fyDai for Dai
    /// The trader needs to have called `fyDai.approve`
    /// @param from Wallet providing the fyDai being sold. Must have approved the operator with `pool.addDelegate(operator)`.
    /// @param to Wallet receiving the dai being bought
    /// @param fyDaiIn Amount of fyDai being sold that will be taken from the user's wallet
    function sellFYDai(address from, address to, uint128 fyDaiIn)
        external override
        onlyHolderOrDelegate(from, "Pool: Only Holder Or Delegate")
        returns(uint128 daiOut)
    {
        daiOut = fyDaiIn * 1e18 / rate;

        fyDai.transferFrom(from, address(this), fyDaiIn);
        dai.transfer(to, daiOut);
    }
}
