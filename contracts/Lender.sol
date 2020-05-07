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
import "./interfaces/IPot.sol";
import "./interfaces/ITreasury.sol";
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

        // vat.hope(address(wethJoin));
        _vat.hope(address(daiJoin_));
        _vat.hope(address(pot_));
    }

    function debt() public returns(uint256) {
        return _debt;
    }

    /// @dev Moves Weth collateral from caller into Lender controlled Maker Eth vault
    function post(uint256 weth) public override {
        post(msg.sender, weth);
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

    /// @dev Moves Weth collateral from Lender controlled Maker Eth vault to caller.
    function withdraw(uint256 weth) public override {
        withdraw(msg.sender, weth);
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

    /// @dev Moves Dai from caller into Lender controlled Maker Dai vault
    function repay(uint256 dai) public override {
        repay(msg.sender, dai);
    }

    /// @dev Moves Dai from `from` address into Lender controlled Maker Dai vault
    function repay(address from, uint256 dai) public override onlyAuthorized("Lender: Not Authorized") {
        require(
            _dai.transferFrom(from, address(this), dai),
            "YToken: DAI transfer fail"
        ); // TODO: Check dai behaviour on failed transfers
        require(
            _debt >= dai,
            "Lender: Not enough debt"
        );
        _daiJoin.join(address(this), dai);
        // Remove debt from vault using frob
        _vat.frob(
            collateralType,
            address(this),
            address(this),
            address(this),
            0,           // Weth collateral to add
            -dai.toInt() // Dai debt to add
        );
        (, _debt) = _vat.urns(collateralType, address(this));
    }

    /// @dev moves Dai from Lender controlled Maker vault, borrowing if necessary, to caller.
    function borrow(uint256 dai) public override {
        borrow(msg.sender, dai);
    }

    /// @dev moves Dai from Lender controlled Maker vault, borrowing if necessary, to `to` address.
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

    /// @dev Moves Dai from user into Treasury controlled Maker Dai vault
    function _repayDai() internal {
        // repay as much debt as possible
        uint256 balance = dai.balanceOf(address(this));
        (, uint256 rate,,,) = vat.ilks(collateralType);
        uint256 normalizedAmount = balance.divd(rate, ray);
        (, uint256 normalizedDebt) = vat.urns(collateralType, address(this));
        //int256 toRepay = Math.min(normalizedAmount, normalizedDebt); // only repay up to total in
        int256 toRepay;
        uint256 toJoin;
        if (normalizedAmount >= normalizedDebt){
            toRepay = -normalizedDebt.toInt();
            toJoin = normalizedDebt.muld(rate, ray);
        } else {
            toRepay = -normalizedAmount.toInt();
            toJoin = balance;

        }
        // TODO: Check dai behaviour on failed transfers
        daiJoin.join(address(this), toJoin);
        // Add Dai to vault
        // collateral to add - wad
        int256 dink = 0;
        // frob alters Maker vaults
        vat.frob(
            collateralType,
            address(this),
            address(this),
            address(this),
            dink,
            toRepay
        ); // `vat.frob` reverts on failure
    }

    /// @dev lock all Dai in the DSR
    function _lockDai() internal {
        uint256 balance = dai.balanceOf(address(this));
        uint256 chi = pot.chi();
        uint256 normalizedAmount = balance.divd(chi, ray);
        daiJoin.join(address(this), normalizedAmount);
        pot.drip();
        pot.join(normalizedAmount);
    }

    /// @dev remove Dai from the DSR
    function _freeDai(uint256 amount) internal {
        uint256 chi = pot.chi();
        uint256 normalizedAmount = amount.divd(chi, ray);
        pot.drip();
        pot.exit(normalizedAmount);
    }
}
