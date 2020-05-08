pragma solidity ^0.6.0;

import "@hq20/contracts/contracts/access/AuthorizedAccess.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@hq20/contracts/contracts/utils/SafeCast.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IDaiJoin.sol";
import "./interfaces/IGemJoin.sol";
import "./interfaces/IVat.sol";
import "./interfaces/ILender.sol";
import "./Constants.sol";


/// @dev Lender manages the Dai, interacting with MakerDAO's vat when needed.
contract Lender is ILender, AuthorizedAccess(), Constants() {
    using DecimalMath for uint256;
    using DecimalMath for int256;
    using DecimalMath for uint8;
    using SafeCast for uint256;
    using SafeCast for int256;

    bytes32 constant collateralType = "ETH-A";

    IERC20 internal _dai;
    IERC20 internal _weth;
    IDaiJoin internal _daiJoin;
    IGemJoin internal _wethJoin;
    IVat internal _vat;

    uint256 internal _debt;

    constructor (address dai_, address weth_, address daiJoin_, address wethJoin_, address vat_) public {
        // These could be hardcoded for mainnet deployment.
        _dai = IERC20(dai_);
        _weth = IERC20(weth_);
        _daiJoin = IDaiJoin(daiJoin_);
        _wethJoin = IGemJoin(wethJoin_);
        _vat = IVat(vat_);
        _vat.hope(address(wethJoin_));
        _vat.hope(address(daiJoin_));

    }

    function debt() public view override returns(uint256) {
        (, uint256 rate,,,) = _vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee
        return _debt.muld(rate, RAY);
    }

    /// @dev Moves Weth collateral from `from` address into Lender controlled Maker Eth vault
    function post(address from, uint256 weth) public override onlyAuthorized("Lender: Not Authorized") {
        require(
            _weth.transferFrom(from, address(this), weth),
            "YToken: WETH transfer fail"
        );
        _weth.approve(address(_wethJoin), weth);
        _wethJoin.join(address(this), weth); // GemJoin reverts if anything goes wrong.
        // All added collateral should be locked into the vault using frob
        _vat.frob(
            collateralType,
            address(this),
            address(this),
            address(this),
            weth.toInt(), // Collateral to add - WAD
            0 // Normalized Dai to receive - WAD
        );
    }

    /// @dev Moves Weth collateral from Lender controlled Maker Eth vault to `to` address.
    function withdraw(address to, uint256 weth) public override onlyAuthorized("Lender: Not Authorized") {
        // Remove collateral from vault using frob
        _vat.frob(
            collateralType,
            address(this),
            address(this),
            address(this),
            -weth.toInt(), // Weth collateral to add - WAD
            0              // Dai debt to add - WAD
        );
        _wethJoin.exit(to, weth); // `GemJoin` reverts on failures
    }

    /// @dev Moves Dai from `from` address into Lender controlled Maker Dai vault
    function repay(address from, uint256 dai) public override onlyAuthorized("Lender: Not Authorized") {
        require(
            debt() >= dai,
            "Lender: Not enough debt"
        );
        require(
            _dai.transferFrom(from, address(this), dai),
            "YToken: DAI transfer fail"
        ); // TODO: Check dai behaviour on failed transfers
        _daiJoin.join(address(this), dai);
        // Remove debt from vault using frob
        (, uint256 rate,,,) = _vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee
        _vat.frob(
            collateralType,
            address(this),
            address(this),
            address(this),
            0,                           // Weth collateral to add
            -dai.divd(rate, RAY).toInt() // Dai debt to add
        );
        (, _debt) = _vat.urns(collateralType, address(this));
    }

    /// @dev borrows Dai from Lender controlled Maker vault, to `to` address.
    function borrow(address to, uint256 dai) public override onlyAuthorized("Lender: Not Authorized") {
        (, uint256 rate,,,) = _vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee
        // Increase the dai debt by the dai to receive divided by the stability fee
        _vat.frob(
            collateralType,
            address(this),
            address(this),
            address(this),
            0,
            dai.divd(rate, RAY).toInt()
        ); // `vat.frob` reverts on failure
        (, _debt) = _vat.urns(collateralType, address(this)); // Doesn't follow checks effects interactions pattern
        _daiJoin.exit(to, dai); // `daiJoin` reverts on failures
    }
}
