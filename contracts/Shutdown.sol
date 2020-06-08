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
    mapping(bytes32 => mapping(address => uint256)) public posted;
    mapping(bytes32 => mapping(uint256 => mapping(address => uint256))) public debtYDai;

    constructor () public {
        _vat.hope(address(_treasury));
        // TODO: A shutdown function in Treasury that forks the MakerDAO vault and transfers all chai.
    }

    /// @dev Takes a series position from Dealer
    function grab(uint256 maturity, bytes32 collateral, address user) public {
        // Copy and delete debtYdai[series][collateral][user]
        // Add and remove inDai(debtYdai[series][collateral][user])*oracles[collateral].price() from/to posted[collateral][user]
    }

    /// @dev Takes any collateral from Dealer, if there are no positions
    function grab(bytes32 collateral, address user) public {
        // Check totalDebtYdai[user] == 0
        // Add and remove posted[collateral][user]
    }

    /// @dev Converts a chai position to a weth one
    function chaiToWeth(uint256 maturity, address user) public {
        
    }

    /// @dev Converts a weth position to a chai one
    function wethToChai(uint256 maturity, address user) public {
        
    }

    /// @dev Repays debt using YDai
    function repay(uint256 maturity, bytes32 collateral, address user, uint256 yDaiAmount) public { }

    /// @dev Repays weth debt using posted collateral. Users might have to convert from chai to weth or viceversa
    /// according to the contract holdings.
    /// posted[WETH][user] = posted[WETH][user] - inDai(debt[WETH][series][user]) * fix[ilk]; delete debt[WETH][series][user]
    /// posted[CHAI][user] = posted[CHAI][user] - inDai(debt[CHAI][series][user] * fix[ilk]) / chi; delete debt[CHAI][series][user]
    function settle(uint256 maturity, bytes32 collateral, address user) public { }

    /// @dev Withdraw free collateral
    function withdraw(bytes32 collateral, address user) public { }
}