pragma solidity ^0.6.0;

// import "@hq20/contracts/contracts/access/AuthorizedAccess.sol";
// import "@hq20/contracts/contracts/math/DecimalMath.sol";
// import "@hq20/contracts/contracts/utils/SafeCast.sol";
// import "@openzeppelin/contracts/access/Ownable.sol";
// import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IDaiJoin.sol";
import "./interfaces/IGemJoin.sol";
// import "./interfaces/IOracle.sol";
import "./interfaces/IEnd.sol";
import "./interfaces/IChai.sol";
import "./interfaces/ITreasury.sol";
// import "./interfaces/IVault.sol";
import "./interfaces/IYDai.sol";
// import "./Constants.sol";
// import "@nomiclabs/buidler/console.sol";


/// @dev Treasury manages the Dai, interacting with MakerDAO's vat and chai when needed.
contract DssShutdown {
    // using DecimalMath for uint256;
    // using DecimalMath for int256;
    // using DecimalMath for uint8;
    // using SafeCast for uint256;
    // using SafeCast for int256;

    bytes32 constant collateralType = "ETH-A";

    IVat internal _vat;
    IDaiJoin internal _daiJoin;
    IERC20 internal _weth;
    IGemJoin internal _wethJoin;
    // IOracle internal _chaiOracle;
    IEnd internal _end;
    IChai internal _chai;
    ITreasury internal _treasury;
    /* IVault internal _chaiDealer;
    IVault internal _wethDealer; */

    mapping(uint256 => IYDai) public series;
    mapping(address => uint256) public posted; // Weth only
    mapping(uint256 => mapping(address => uint256)) public debtYDai;

    constructor (
        address vat_,
        address daiJoin_,
        address weth_,
        address wethJoin_,
        address end_,
        address chai_,
        address treasury_
    ) public {
        // These could be hardcoded for mainnet deployment.
        _vat = IVat(vat_);
        _daiJoin = IDaiJoin(daiJoin_);
        _weth = IERC20(weth_);
        _wethJoin = IGemJoin(wethJoin_);
        _end = IEnd(end_);
        _chai = IChai(chai_);
        _treasury = ITreasury(treasury_);
        // _dai = IERC20(dai_);
        // _chaiOracle = IOracle(chaiOracle_);

        _vat.hope(address(_treasury));
        _vat.hope(address(_end));
        // Treasury gives permissions to DssShutdown on the constructor as well.
    }

    /// @dev Settle system debt in MakerDAO and free remaining collateral.
    function settleTreasury() public {
        require(
            _end.tag(collateralType) != 0,
            "DssShutdown: End.sol not caged"
        );
        _end.skim(collateralType, address(_treasury));           // Settle debts
        _end.free(collateralType);                               // Free collateral
        // (uint256 ink,) = _vat.urns("ETH-A", address(_treasury));
        // _wethJoin.exit(address(_treasury), ink);                 // Take collateral from Treasury
    }

    /// @dev Put all chai savings in MakerDAO and exchange them for weth
    function cashSavings() public {
        require(
            _end.tag(collateralType) != 0,
            "DssShutdown: End.sol not caged"
        );
        require(
            _end.fix(collateralType) != 0,
            "DssShutdown: End.sol not ready"
        );
        uint256 daiTokens = _chai.dai(address(_treasury));   // Find out how much is the chai worth
        _chai.draw(address(_treasury), _treasury.savings()); // Get the chai as dai
        _daiJoin.join(address(this), daiTokens);             // Put the dai into MakerDAO
        _end.pack(daiTokens);                                // Into End.sol, more exactly
        _end.cash(collateralType, daiTokens);                // Exchange the dai for weth
        // (uint256 ink,) = _vat.urns("ETH-A", address(this));
        // _wethJoin.exit(address(this), ink);                  // Take weth out
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