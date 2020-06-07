pragma solidity ^0.6.0;

import "@hq20/contracts/contracts/access/AuthorizedAccess.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@hq20/contracts/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IChai.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITreasury.sol";
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
    IDealer internal _chaiDealer;
    IDealer internal _wethDealer;

    mapping(uint256 => YDai) public series;
    mapping(bytes32 => mapping(address => uint256)) public posted;
    mapping(bytes32 => mapping(uint256 => mapping(address => uint256)) public debtYDai;

    constructor () public {
        _vat.hope(address(_treasury));
        // TODO: A shutdown function in Treasury that forks the MakerDAO vault and transfers all chai.
    }

    /// @dev Takes a series position from Dealer
    function grab(series, collateral, user) public {
        // Copy and delete debtYdai[series][collateral][user]
        // Add and remove inDai(debtYdai[series][collateral][user])*oracles[collateral].price() from/to posted[collateral][user]
    }

    /// @dev Takes any collateral from Dealer, if there are no positions
    function grab(collateral, user) public {
        // Check totalDebtYdai[user] == 0
        // Add and remove posted[collateral][user]
    }

    /// @dev Converts a chai position to a weth one
    function chaiToWeth(series, user) public {
        
    }

    /// @dev Converts a weth position to a chai one
    function wethToChai(series, user) public {
        
    }

    /// @dev Repays debt using YDai
    function repay(series, collateral, user, yDaiAmount) public { }

    /// @dev Repays weth debt using posted collateral. Users might have to convert from chai to weth or viceversa
    /// according to the contract holdings.
    /// posted[WETH][user] = posted[WETH][user] - inDai(debt[WETH][series][user]) * fix[ilk]; delete debt[WETH][series][user]
    /// posted[CHAI][user] = posted[CHAI][user] - inDai(debt[CHAI][series][user] * fix[ilk]) / chi; delete debt[CHAI][series][user]
    function settle(series, collateral, user) public { }

    /// @dev Withdraw free collateral
    function withdraw(collateral, user) public { }
}