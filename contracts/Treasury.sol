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
import "./interfaces/IChai.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/ITreasury.sol";
import "./Constants.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev Treasury manages the Dai, interacting with MakerDAO's vat and chai when needed.
contract Treasury is ITreasury, AuthorizedAccess(), Constants() {
    using DecimalMath for uint256;
    using DecimalMath for int256;
    using DecimalMath for uint8;
    using SafeCast for uint256;
    using SafeCast for int256;

    bytes32 constant collateralType = "ETH-A";

    IERC20 internal _dai;
    IChai internal _chai;
    IOracle internal _chaiOracle;
    IERC20 internal _weth;
    IDaiJoin internal _daiJoin;
    IGemJoin internal _wethJoin;
    IVat internal _vat;

    constructor (
        address dai_,
        address chai_,
        address chaiOracle_,
        address weth_,
        address daiJoin_,
        address wethJoin_,
        address vat_
    ) public {
        // These could be hardcoded for mainnet deployment.
        _dai = IERC20(dai_);
        _chai = IChai(chai_);
        _chaiOracle = IOracle(chaiOracle_);
        _weth = IERC20(weth_);
        _daiJoin = IDaiJoin(daiJoin_);
        _wethJoin = IGemJoin(wethJoin_);
        _vat = IVat(vat_);
        _vat.hope(address(wethJoin_));
        _vat.hope(address(daiJoin_));

    }

    /// @dev Returns the Treasury debt towards MakerDAO, as the dai borrowed times the stability fee for Weth.
    /// We have borrowed (rate * art)
    /// Borrowing Limit (rate * art) <= (ink * spot)
    function debt() public view returns(uint256) {
        (, uint256 rate,,,) = _vat.ilks("ETH-A");            // Retrieve the MakerDAO stability fee for Weth
        (, uint256 art) = _vat.urns("ETH-A", address(this)); // Retrieve the Treasury debt in MakerDAO
        return art.muld(rate, RAY);
    }

    /// @dev Returns the Treasury borrowing capacity from MakerDAO, as the collateral posted times the collateralization ratio for Weth.
    /// We can borrow (ink * spot)
    function power() public view returns(uint256) {
        (,, uint256 spot,,) = _vat.ilks("ETH-A");            // Collateralization ratio for Weth
        (uint256 ink,) = _vat.urns("ETH-A", address(this));  // Treasury Weth collateral in MakerDAO
        return ink.muld(spot, RAY);
    }

    /// @dev Returns the amount of Dai in this contract.
    function savings() public returns(uint256){
        return _chai.dai(address(this));
    }

    /// @dev Pays as much system debt as possible from the Treasury dai balance, saving the rest as chai.
    function pushDai() public override onlyAuthorized("Treasury: Not Authorized") {
        uint256 dai = _dai.balanceOf(address(this));

        uint256 toRepay = Math.min(debt(), dai);
        if (toRepay > 0) {
            _daiJoin.join(address(this), toRepay);
            // Remove debt from vault using frob
            (, uint256 rate,,,) = _vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee
            _vat.frob(
                collateralType,
                address(this),
                address(this),
                address(this),
                0,                           // Weth collateral to add
                -toRepay.divd(rate, RAY).toInt() // Dai debt to remove
            );
        }

        uint256 toSave = dai - toRepay;         // toRepay can't be greater than dai
        if (toSave > 0) {
            _dai.approve(address(_chai), toSave); // Chai will take dai
            _chai.join(address(this), toSave);    // Give dai to Chai, take chai back
        }
    }

    /// @dev Pays as much system debt as possible from the Treasury chai balance, saving the rest as chai.
    function pushChai() public override onlyAuthorized("Treasury: Not Authorized") {
        uint256 dai = _chai.dai(address(this));

        uint256 toRepay = Math.min(debt(), dai);
        if (toRepay > 0) {
            _chai.draw(address(this), toRepay);     // Grab dai from Chai, converted from chai
            _daiJoin.join(address(this), toRepay);
            // Remove debt from vault using frob
            (, uint256 rate,,,) = _vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee
            _vat.frob(
                collateralType,
                address(this),
                address(this),
                address(this),
                0,                           // Weth collateral to add
                -toRepay.divd(rate, RAY).toInt() // Dai debt to remove
            );
        }
        // Anything that is left from repaying, is chai savings
    }

    /// @dev Returns dai using chai savings as much as possible, and borrowing the rest.
    function pullDai(address user, uint256 dai) public override onlyAuthorized("Treasury: Not Authorized") {
        uint256 toRelease = Math.min(savings(), dai);
        if (toRelease > 0) {
            _chai.draw(address(this), toRelease);     // Grab dai from Chai, converted from chai
        }

        uint256 toBorrow = dai - toRelease;    // toRelease can't be greater than dai
        if (toBorrow > 0) {
            (, uint256 rate,,,) = _vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee
            // Increase the dai debt by the dai to receive divided by the stability fee
            _vat.frob(
                collateralType,
                address(this),
                address(this),
                address(this),
                0,
                toBorrow.divd(rate, RAY).toInt()
            ); // `vat.frob` reverts on failure
            _daiJoin.exit(address(this), toBorrow); // `daiJoin` reverts on failures
        }

        require(                            // Give dai to user
            _dai.transfer(user, dai),
            "Treasury: Dai transfer fail"
        );
    }

    /// @dev Returns chai using chai savings as much as possible, and borrowing the rest.
    function pullChai(address user, uint256 chai) public override onlyAuthorized("Treasury: Not Authorized") {
        uint256 dai = chai.divd(_chaiOracle.price(), RAY);   // dai = chai * price
        uint256 toRelease = Math.min(savings(), dai);
        // As much chai as the Treasury has, can be used, we borrwo dai and convert it to chai for the rest

        uint256 toBorrow = dai - toRelease;    // toRelease can't be greater than dai
        if (toBorrow > 0) {
            (, uint256 rate,,,) = _vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee
            // Increase the dai debt by the dai to receive divided by the stability fee
            _vat.frob(
                collateralType,
                address(this),
                address(this),
                address(this),
                0,
                toBorrow.divd(rate, RAY).toInt()
            ); // `vat.frob` reverts on failure
            _daiJoin.exit(address(this), toBorrow);  // `daiJoin` reverts on failures
            _dai.approve(address(_chai), toBorrow);   // Chai will take dai
            _chai.join(address(this), toBorrow);     // Grab chai from Chai, converted from dai
        }

        require(                            // Give dai to user
            _chai.transfer(user, chai),
            "Treasury: Chai transfer fail"
        );
    }

    /// @dev Moves all Weth collateral from Treasury into Maker
    function pushWeth() public override onlyAuthorized("Treasury: Not Authorized") {
        uint256 weth = _weth.balanceOf(address(this));

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

    /// @dev Moves Weth collateral from Treasury controlled Maker Eth vault to `to` address.
    function pullWeth(address to, uint256 weth) public override onlyAuthorized("Treasury: Not Authorized") {
        // Remove collateral from vault using frob
        _vat.frob(
            collateralType,
            address(this),
            address(this),
            address(this),
            -weth.toInt(), // Weth collateral to remove - WAD
            0              // Dai debt to add - WAD
        );
        _wethJoin.exit(to, weth); // `GemJoin` reverts on failures
    }
}