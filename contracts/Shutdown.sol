pragma solidity ^0.6.0;

import "@hq20/contracts/contracts/access/AuthorizedAccess.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@hq20/contracts/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IEnd.sol";
import "./interfaces/IChai.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IVault.sol";
import "./interfaces/IYDai.sol";
import "./Constants.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev Treasury manages the Dai, interacting with MakerDAO's vat and chai when needed.
contract Shutdown is Constants() {
    using DecimalMath for uint256;
    using DecimalMath for int256;
    using DecimalMath for uint8;
    using SafeCast for uint256;
    using SafeCast for int256;

    bytes32 constant collateralType = "ETH-A";

    IVat internal _vat;
    IERC20 internal _weth;
    IChai internal _chai;
    IOracle internal _chaiOracle;
    IEnd internal _end;
    ITreasury internal _treasury;
    IVault internal _chaiDealer;
    IVault internal _wethDealer;

    mapping(uint256 => IYDai) public series;
    mapping(address => uint256) public posted; // Weth only
    mapping(uint256 => mapping(address => uint256)) public debtYDai;

    constructor () public {
        _vat.hope(address(_treasury));
        // TODO: A shutdown function in Treasury that forks the MakerDAO vault and transfers all chai.
    }

    /// @dev Settle system debt in MakerDAO
    function dissolveDebt() public {
        // Skim treasury's position
    }

    /// @dev Put all chai savings in MakerDAO
    function dissolveSavings() public {
        // Requires no system debt
        // Convert savings from treasury into dai for shutdown
        // Pack all dai in MakerDAO
        // Cash all dai as weth
    }

    /// @dev Takes a series position from Dealer
    function grab(uint256 maturity, bytes32 collateral, address user) public {
        // Copy and delete debtYdai[series][collateral][user] using `_dealer.settle`
        // debt[maturity][user](yDai) = debt[maturity][user] + `_dealer.settle.debt` TODO: Return as YDai as well
        // posted[user] = posted[user] + `_dealer.settle.tokenAmount` (if weth)
        // posted[user] = posted[user] + chaiToWeth(`_dealer.settle.tokenAmount`) (if chai)
    }

    /// @dev Takes any collateral from Dealer, if there are no positions
    function grab(bytes32 collateral, address user) public {
        // Check totalDebtYdai[user] == 0
        // Remove posted[collateral][user] using `_dealer.grab`
        // posted[user] = posted[user] + `_dealer.settle.tokenAmount` (if weth)
        // posted[user] = posted[user] + chaiToWeth(`_dealer.settle.tokenAmount`) (if chai)
    }

    /// @dev Converts a chai position to a weth one
    function chaiToWeth() public {
        // dai = chi * chai
        // dai = spot * weth
        // weth = (chi / spot) * chai
        // Or: weth = (chi * fix[ilk]) * chai
    }

    /// @dev Repays debt using YDai
    /// TODO: Needs to be done before merging debt from all series
    function repay(uint256 maturity, address user, uint256 yDaiAmount) public {
        // debt[maturity][user] = debt[maturity][user] - yDaiAmount
    }

    /// @dev Redeems YDai for weth
    /// TODO: Needs to be done before merging debt from all series
    function redeem(uint256 maturity, uint256 yDaiAmount) public {
        // inDai(maturity, yDaiAmount) * fix[ilk]
    }

    /// @dev Repays weth debt using posted collateral.
    function settle(address user) public {
        // posted[user] = posted[user] - inDai(debt[maturity][user]) * fix[ilk]; delete debt[maturity][user]
        // if not enough posted[user] enter liquidation
    }

    /// @dev Withdraw free collateral
    function withdraw(bytes32 collateral, address user) public {
        // Requires no system savings
        // Requires no user debt
        // Call wethJoin to deliver weth as posted[user]
    }
}