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
import "./interfaces/ILender.sol";
import "./interfaces/ISaver.sol";
import "./Constants.sol";


/// @dev Treasury manages the Dai, interacting with MakerDAO's vat when needed.
contract Treasury is ILender, ISaver, AuthorizedAccess(), Constants() {
    using DecimalMath for uint256;
    using DecimalMath for int256;
    using DecimalMath for uint8;
    using SafeCast for uint256;
    using SafeCast for int256;

    bytes32 constant collateralType = "ETH-A";

    IERC20 internal _dai;
    IChai internal _chai;
    IERC20 internal _weth;
    IDaiJoin internal _daiJoin;
    IGemJoin internal _wethJoin;
    IVat internal _vat;

    constructor (
        address dai_,
        address chai_,
        address weth_,
        address daiJoin_,
        address wethJoin_,
        address vat_
    ) public {
        // These could be hardcoded for mainnet deployment.
        _dai = IERC20(dai_);
        _chai = IChai(chai_);
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
    function debt() public view override returns(uint256) {
        (, uint256 rate,,,) = _vat.ilks("ETH-A");            // Retrieve the MakerDAO stability fee for Weth
        (, uint256 art) = _vat.urns("ETH-A", address(this)); // Retrieve the Treasury debt in MakerDAO
        return art.muld(rate, RAY);
    }

    /// @dev Returns the Treasury borrowing capacity from MakerDAO, as the collateral posted times the collateralization ratio for Weth.
    /// We can borrow (ink * spot)
    function power() public view override returns(uint256) {
        (,, uint256 spot,,) = _vat.ilks("ETH-A");            // Collateralization ratio for Weth
        (uint256 ink,) = _vat.urns("ETH-A", address(this));  // Treasury Weth collateral in MakerDAO
        return ink.muld(spot, RAY);
    }

    /// @dev Returns the amount of Dai in this contract.
    function savings() public override returns(uint256){
        return _chai.dai(address(this));
    }

    // Anyone can send chai to saver, no way of stopping it

    /// @dev Moves Dai into the contract and converts it to Chai
    function hold(address user, uint256 dai) public override onlyAuthorized("Treasury: Not Authorized") {
        require(
            _dai.transferFrom(user, address(this), dai),
            "Treasury: Chai transfer fail"
        );                                 // Take dai from user
        _dai.approve(address(_chai), dai); // Chai will take dai
        _chai.join(address(this), dai);    // Give dai to Chai, take chai back
    }

    /// @dev Gives chai to the user
    function releaseChai(address user, uint256 chai) public override onlyAuthorized("Treasury: Not Authorized") {
        require(
            _chai.transfer(user, chai),    // Give chai to user
            "Treasury: Chai transfer fail"
        );
    }

    /// @dev Converts Chai to Dai and gives it to the user
    function release(address user, uint256 dai) public override onlyAuthorized("Treasury: Not Authorized") {
        _chai.draw(address(this), dai);     // Grab dai from Chai, converted from chai
        require(                            // Give dai to user
            _dai.transfer(user, dai),
            "Treasury: Dai transfer fail"
        );
    }

    /// @dev Moves Weth collateral from `from` address into Treasury controlled Maker Eth vault
    function post(address from, uint256 weth) public override onlyAuthorized("Treasury: Not Authorized") {
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

    /// @dev Moves Weth collateral from Treasury controlled Maker Eth vault to `to` address.
    function withdraw(address to, uint256 weth) public override onlyAuthorized("Treasury: Not Authorized") {
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

    /// @dev Moves Dai from `from` address into Treasury controlled Maker Dai vault
    function repay(address from, uint256 dai) public override onlyAuthorized("Treasury: Not Authorized") {
        require(
            debt() >= dai,
            "Treasury: Not enough debt"
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
    }

    /// @dev borrows Dai from Treasury controlled Maker vault, to `to` address.
    // TODO: Check that the Treasury has posted enough collateral to borrow the dai
    function borrow(address to, uint256 dai) public override onlyAuthorized("Treasury: Not Authorized") {
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
        _daiJoin.exit(to, dai); // `daiJoin` reverts on failures
    }
}