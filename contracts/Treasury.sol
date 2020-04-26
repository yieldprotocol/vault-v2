pragma solidity ^0.5.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IDaiJoin.sol";
import "./interfaces/IGemJoin.sol";
import "./interfaces/IVat.sol";


contract Treasury {
    using DecimalMath for uint256;
    using DecimalMath for int256;
    using DecimalMath for uint8;

    IERC20 public weth;
    IERC20 public dai;
    // Maker join contracts:
    // https://github.com/makerdao/dss/blob/master/src/join.sol
    IGemJoin public wethJoin;
    IDaiJoin public daiJoin;
    // Maker vat contract:
    IVat public vat;

    int256 daiBalance; // Could this be retrieved as dai.balanceOf(address(this)) - something?
    // uint256 ethBalance; // This can be retrieved as weth.balanceOf(address(this))
    bytes32 collateralType = "ETH-A";

    // TODO: Move to Constants.sol
    // Fixed point256 precisions from MakerDao
    uint8 constant public wad = 18;
    uint8 constant public ray = 27;
    uint8 constant public rad = 45;

    uint256 public rate; // accumulator (for stability fee) at maturity in ray units

    /// @dev Moves Eth collateral from user into Treasury controlled Maker Eth vault
    function post(address from, uint256 amount) public {
        require(
            weth.transferFrom(from, address(this), amount),
            "YToken: WETH transfer fail"
        );
        weth.approve(address(wethJoin), amount);
        wethJoin.join(address(this), amount); // GemJoin reverts if anything goes wrong.
        // All added collateral should be locked into the vault
        // collateral to add - wad
        int256 dink = int256(amount); // Can't be negative because `amount` is a uint
        // Normalized Dai to receive - wad
        int256 dart = 0;
        // frob alters Maker vaults
        vat.frob(
            collateralType,
            address(this),
            address(this),
            address(this),
            dink,
            dart
        ); // `vat.frob` reverts on failure
    }

    /// @dev Moves Eth collateral from Treasury controlled Maker Eth vault back to user
    function withdraw(address receiver, uint256 amount) public {
        // Remove collateral from vault
        // collateral to add - wad
        int256 dink = -int256(amount); // `amount` must be positive since it is an uint
        // Normalized Dai to receive - wad
        int256 dart = 0;
        // frob alters Maker vaults
        vat.frob(
            collateralType,
            address(this),
            address(this),
            address(this),
            dink,
            dart
        ); // `vat.frob` reverts on failure
        wethJoin.exit(receiver, amount); // `GemJoin` reverts on failures
    }

    /// @dev Moves Dai from user into Treasury controlled Maker Dai vault
    function repay(address source, uint256 amount) public {
        require(
            dai.transferFrom(source, address(this), amount),
            "YToken: DAI transfer fail"
        ); // TODO: Check dai behaviour on failed transfers
        // No need for `dai.approve(address(daiJoin), amount)?
        daiJoin.join(address(this)); // `daiJoin.join` doesn't pass an amount as a parameter?
        // Add Dai to vault
        // collateral to add - wad
        int256 dink = 0;

        // Normalized Dai to receive - wad
        (, rate,,,) = vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee
        int256 dart = -int256(amount.divd(rate, ray)); // `amount` and `rate` are positive
        // frob alters Maker vaults
        vat.frob(
            collateralType,
            address(this),
            address(this),
            address(this),
            dink,
            dart
        ); // `vat.frob` reverts on failure
    }

    /// @dev Mint256 an `amount` of Dai
    function _generateDai(address receiver, uint256 amount) private {
        // Add Dai to vault
        // collateral to add - wad
        int256 dink = 0; // Delta ink, change in collateral balance
        // Normalized Dai to receive - wad
        (, rate,,,) = vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee
        // collateral to add -- all collateral should already be present
        int256 dart = -int256(amount.divd(rate, ray)); // Delta art, change in dai debt
        // Normalized Dai to receive - wad
        // frob alters Maker vaults
        vat.frob(
            collateralType,
            address(this),
            address(this),
            address(this),
            dink,
            dart
        ); // `vat.frob` reverts on failure
        daiJoin.exit(receiver, amount); // `daiJoin` reverts on failures
    }

    /// @dev moves Dai from Treasury to user, borrowing from Maker DAO if not enough present.
    function disburse(address receiver, uint256 amount) public {
        int256 toSend = int256(amount);
        require(
            toSend >= 0,
            "YToken: Invalid amount"
        );
        if (daiBalance > toSend) {
            //send funds directly
            require(
                dai.transfer(receiver, amount),
                "YToken: DAI transfer fail"
            ); // TODO: Check dai behaviour on failed transfers
        } else {
            //borrow funds and send them
            _generateDai(receiver, amount);
        }
    }
}