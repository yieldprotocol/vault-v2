pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IVat.sol";
import "./interfaces/IDaiJoin.sol";
import "./interfaces/IGemJoin.sol";
import "./interfaces/IPot.sol";
import "./interfaces/IChai.sol";
import "./interfaces/ITreasury.sol";
import "./helpers/DecimalMath.sol";
import "./helpers/Orchestrated.sol";
import "@nomiclabs/buidler/console.sol";


/// @dev Treasury manages the Dai, interacting with MakerDAO's vat and chai when needed.
contract Treasury is ITreasury, Orchestrated(), DecimalMath {
    bytes32 constant WETH = "ETH-A";

    IERC20 internal _dai;
    IChai internal _chai;
    IPot internal _pot;
    IERC20 internal _weth;
    IDaiJoin internal _daiJoin;
    IGemJoin internal _wethJoin;
    IVat internal _vat;
    address internal _unwind;

    bool public override live = true;

    constructor (
        address vat_,
        address weth_,
        address dai_,
        address wethJoin_,
        address daiJoin_,
        address pot_,
        address chai_
    ) public {
        // These could be hardcoded for mainnet deployment.
        _dai = IERC20(dai_);
        _chai = IChai(chai_);
        _pot = IPot(pot_);
        _weth = IERC20(weth_);
        _daiJoin = IDaiJoin(daiJoin_);
        _wethJoin = IGemJoin(wethJoin_);
        _vat = IVat(vat_);
        _vat.hope(wethJoin_);
        _vat.hope(daiJoin_);

        _dai.approve(address(_chai), uint256(-1));      // Chai will never cheat on us
        _weth.approve(address(_wethJoin), uint256(-1)); // WethJoin will never cheat on us
    }

    modifier onlyLive() {
        require(live == true, "Treasury: Not available during unwind");
        _;
    }

    /// @dev Safe casting from uint256 to int256
    function toInt(uint256 x) internal pure returns(int256) {
        require(
            x <= 57896044618658097711785492504343953926634992332820282019728792003956564819967,
            "Treasury: Cast overflow"
        );
        return int256(x);
    }

    /// @dev Disables pulling and pushing. Can only be called if MakerDAO shuts down.
    function shutdown() public override {
        require(
            _vat.live() == 0,
            "Treasury: MakerDAO is live"
        );
        live = false;
    }

    /// @dev Returns the Treasury debt towards MakerDAO, as the dai borrowed times the stability fee for Weth.
    /// We have borrowed (rate * art)
    /// Borrowing Limit (rate * art) <= (ink * spot)
    function debt() public view override returns(uint256) {
        (, uint256 rate,,,) = _vat.ilks(WETH);            // Retrieve the MakerDAO stability fee for Weth
        (, uint256 art) = _vat.urns(WETH, address(this)); // Retrieve the Treasury debt in MakerDAO
        return muld(art, rate);
    }

    /// @dev Returns the Treasury borrowing capacity from MakerDAO, as the collateral posted times the collateralization ratio for Weth.
    /// We can borrow (ink * spot)
    function power() public view returns(uint256) {
        (,, uint256 spot,,) = _vat.ilks(WETH);            // Collateralization ratio for Weth
        (uint256 ink,) = _vat.urns(WETH, address(this));  // Treasury Weth collateral in MakerDAO
        return muld(ink, spot);
    }

    /// @dev Returns the amount of Dai in this contract.
    function savings() public override returns(uint256){
        return _chai.dai(address(this));
    }

    /// @dev Takes dai from user and pays as much system debt as possible, saving the rest as chai.
    function pushDai(address from, uint256 amount) public override onlyOrchestrated("Treasury: Not Authorized") onlyLive  {
        require(
            _dai.transferFrom(from, address(this), amount),  // Take dai from user to Treasury
            "Controller: Dai transfer fail"
        );

        uint256 toRepay = Math.min(debt(), amount);
        if (toRepay > 0) {
            _daiJoin.join(address(this), toRepay);
            // Remove debt from vault using frob
            (, uint256 rate,,,) = _vat.ilks(WETH); // Retrieve the MakerDAO stability fee
            _vat.frob(
                WETH,
                address(this),
                address(this),
                address(this),
                0,                           // Weth collateral to add
                -toInt(divd(toRepay, rate))  // Dai debt to remove
            );
        }

        uint256 toSave = amount - toRepay;         // toRepay can't be greater than dai
        if (toSave > 0) {
            _chai.join(address(this), toSave);    // Give dai to Chai, take chai back
        }
    }

    /// @dev Takes chai from user and pays as much system debt as possible, saving the rest as chai.
    function pushChai(address from, uint256 amount) public override onlyOrchestrated("Treasury: Not Authorized") onlyLive  {
        require(
            _chai.transferFrom(from, address(this), amount),
            "Treasury: Chai transfer fail"
        );
        uint256 dai = _chai.dai(address(this));

        uint256 toRepay = Math.min(debt(), dai);
        if (toRepay > 0) {
            _chai.draw(address(this), toRepay);     // Grab dai from Chai, converted from chai
            _daiJoin.join(address(this), toRepay);
            // Remove debt from vault using frob
            (, uint256 rate,,,) = _vat.ilks(WETH); // Retrieve the MakerDAO stability fee
            _vat.frob(
                WETH,
                address(this),
                address(this),
                address(this),
                0,                           // Weth collateral to add
                -toInt(divd(toRepay, rate))  // Dai debt to remove
            );
        }
        // Anything that is left from repaying, is chai savings
    }

    /// @dev Takes Weth collateral from user into the system Maker vault
    function pushWeth(address from, uint256 amount) public override onlyOrchestrated("Treasury: Not Authorized") onlyLive  {
        require(
            _weth.transferFrom(from, address(this), amount),
            "Treasury: Weth transfer fail"
        );

        _wethJoin.join(address(this), amount); // GemJoin reverts if anything goes wrong.
        // All added collateral should be locked into the vault using frob
        _vat.frob(
            WETH,
            address(this),
            address(this),
            address(this),
            toInt(amount), // Collateral to add - WAD
            0 // Normalized Dai to receive - WAD
        );
    }

    /// @dev Returns dai using chai savings as much as possible, and borrowing the rest.
    function pullDai(address to, uint256 dai) public override onlyOrchestrated("Treasury: Not Authorized") onlyLive  {
        uint256 toRelease = Math.min(savings(), dai);
        if (toRelease > 0) {
            _chai.draw(address(this), toRelease);     // Grab dai from Chai, converted from chai
        }

        uint256 toBorrow = dai - toRelease;    // toRelease can't be greater than dai
        if (toBorrow > 0) {
            (, uint256 rate,,,) = _vat.ilks(WETH); // Retrieve the MakerDAO stability fee
            // Increase the dai debt by the dai to receive divided by the stability fee
            _vat.frob(
                WETH,
                address(this),
                address(this),
                address(this),
                0,
                toInt(divd(toBorrow, rate))
            ); // `vat.frob` reverts on failure
            _daiJoin.exit(address(this), toBorrow); // `daiJoin` reverts on failures
        }

        require(                            // Give dai to user
            _dai.transfer(to, dai),
            "Treasury: Dai transfer fail"
        );
    }

    /// @dev Returns chai using chai savings as much as possible, and borrowing the rest.
    function pullChai(address to, uint256 chai) public override onlyOrchestrated("Treasury: Not Authorized") onlyLive  {
        uint256 chi = (now > _pot.rho()) ? _pot.drip() : _pot.chi();
        uint256 dai = muld(chai, chi);   // dai = price * chai
        uint256 toRelease = Math.min(savings(), dai);
        // As much chai as the Treasury has, can be used, we borrwo dai and convert it to chai for the rest

        uint256 toBorrow = dai - toRelease;    // toRelease can't be greater than dai
        if (toBorrow > 0) {
            (, uint256 rate,,,) = _vat.ilks(WETH); // Retrieve the MakerDAO stability fee
            // Increase the dai debt by the dai to receive divided by the stability fee
            _vat.frob(
                WETH,
                address(this),
                address(this),
                address(this),
                0,
                toInt(divd(toBorrow, rate))
            ); // `vat.frob` reverts on failure
            _daiJoin.exit(address(this), toBorrow);  // `daiJoin` reverts on failures
            _chai.join(address(this), toBorrow);     // Grab chai from Chai, converted from dai
        }

        require(                            // Give dai to user
            _chai.transfer(to, chai),
            "Treasury: Chai transfer fail"
        );
    }

    /// @dev Moves Weth collateral from Treasury controlled Maker Eth vault to `to` address.
    function pullWeth(address to, uint256 weth) public override onlyOrchestrated("Treasury: Not Authorized") onlyLive  {
        // Remove collateral from vault using frob
        _vat.frob(
            WETH,
            address(this),
            address(this),
            address(this),
            -toInt(weth), // Weth collateral to remove - WAD
            0              // Dai debt to add - WAD
        );
        _wethJoin.exit(to, weth); // `GemJoin` reverts on failures
    }

    /// @dev Registers the one contract that will take assets from the Treasury if MakerDAO shuts down.
    function registerUnwind(address unwind_) public onlyOwner {
        require(
            _unwind == address(0),
            "Treasury: Unwind already set"
        );
        _unwind = unwind_;
        _chai.approve(address(_unwind), uint256(-1)); // Unwind will never cheat on us
        _vat.hope(address(_unwind));                  // Unwind will never cheat on us
    }
}