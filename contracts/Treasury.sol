pragma solidity ^0.5.2;

import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./interfaces/IVat.sol";


contract Treasury {
    using DecimalMath for int256;

    IWETH    public weth;
    IDAI     public dai;
    // Maker join contracts:
    // https://github.com/makerdao/dss/blob/master/src/join.sol
    IEthJoin public ethjoin;
    IDaiJoin public daiJoin;
    // Maker vat contract:
    IVat public vat;

    int256 daiBalance;
    uint256 ethBalance;
    bytes32 collateralType = "ETH-A";

    // TODO: Move to Constants.sol
    // Fixed point precisions from MakerDao
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
        weth.approve(address(ethjoin), amount);
        require(
            ethjoin.join(address(this), amount),
            "YToken: ETH join failed"
        );
        // All added collateral should be locked into the vault
        // collateral to add - wad
        int dink = int(amount);
        require(
            dink >= 0,
            "YToken: Invalid amount"
        );
        // Normalized Dai to receive - wad
        int dart = 0;
        // frob alters Maker vaults
        require(
            vat.frob(
                collateralType,
                address(this),
                address(this),
                address(this),
                dink,
                dart
            ),
            "YToken: vault update failed"
        );
        ethBalance += amount;
    }

    /// @dev Moves Eth collateral from Treasury controlled Maker Eth vault back to user
    function withdraw(address dst, uint256 amount) public {
        // Remove collateral from vault
        // collateral to add - wad
        int dink = -int(amount);
        require(
            dink <= 0,
            "YToken: Invalid amount"
        );
        // Normalized Dai to receive - wad
        int dart = 0;
        // frob alters Maker vaults
        require(
            vat.frob(
                collateralType,
                address(this),
                address(this),
                address(this),
                dink,
                dart
            ),
            "YToken: vault update failed"
        );
        require(
            ethjoin.exit(dst, amount),
            "YToken: ETH exit failed"
        );
        // Don't we need a weth.transferFrom() here?
        ethBalance -= amount;
    }

    /// @dev Moves Dai from user into Treasury controlled Maker Dai vault
    function repay(address source, uint256 amount) public {
        require(
            dai.transferFrom(source, address(this), amount),
            "YToken: DAI transfer fail"
        );
        require(
            daiJoin.join(address(this), amount),
            "YToken: DAI join failed"
        );
        // Add Dai to vault
        // collateral to add - wad
        int dink = 0;

        // Normalized Dai to receive - wad
        (, rate,,,) = vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee
        int dart = -int(amount.divd(rate, ray.unit()));
        require(
            dart <= 0,
            "YToken: Invalid amount"
        );
        // frob alters Maker vaults
        require(
            vat.frob(
                collateralType,
                address(this),
                address(this),
                address(this),
                dink,
                dart
            ),
            "YToken: vault update failed"
        );

    }

    /// @dev Mint an `amount` of Dai
    function _generateDai(address dst, uint256 amount) private {
        // Add Dai to vault
        // collateral to add - wad
        int dink = 0; // Delta ink, change in collateral balance
        // Normalized Dai to receive - wad
        (, rate,,,) = vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee
        // collateral to add -- all collateral should already be present
        int dart = -int(amount.divd(rate, ray.unit())); // Delta art, change in dai debt
        require(
            dart <= 0,
            "YToken: Invalid amount"
        );
        // Normalized Dai to receive - wad
        // frob alters Maker vaults
        require(
            vat.frob(
                collateralType,
                address(this),
                address(this),
                address(this),
                dink,
                dart
            ),
            "YToken: vault update failed"
        );
        require(
            daiJoin.exit(address(this), amount),
            "YToken: DAI exit failed"
        );
        require(
            dai.transferFrom(source, address(this), amount),
            "YToken: DAI transfer fail"
        );
    }

    /// @dev moves Dai from Treasury to user, borrowing from Maker DAO if not enough present.
    function disburse(address receiver, uint256 amount) public {
        int toSend = int(amount);
        require(
            toSend >= 0,
            "YToken: Invalid amount"
        );
        if (daiBalance > toSend) {
            //send funds directly
        } else {
            //borrow funds and send them
            _generateDai(receiver, amount);
        }
    }
}