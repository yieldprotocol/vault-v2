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

    /// @dev moves collateral from user into Treasury controlled vault
    function postCollateral(address from, uint256 amount) public {
        require(
            weth.transferFrom(from, address(this), amount),
            "YToken: WETH transfer fail"
        );
        weth.approve(address(ethjoin), amount);
        require(
            ethjoin.join(address(this), amount),
            "YToken: ETHJOIN failed"
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
            dart),
            "YToken: vault update failed"
        );
        ethBalance += amount;
    }

    /// @dev moves collateral from Treasury controlled vault back to user
    function withdrawCollateral(address dst, uint256 amount) public {
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
            dart),
            "YToken: vault update failed"
        );
        require(
            ethjoin.exit(dst, amount),
            "YToken: ETHJOIN failed"
        );
        ethBalance -= amount;
    }

    function repayDai(address source, uint256 amount) public {
        require(
            dai.transferFrom(source, address(this), amount),
            "YToken: WETH transfer fail"
        );
        require(
            daiJoin.join(address(this), amount),
            "YToken: ETHJOIN failed"
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
            dart),
            "YToken: vault update failed"
        );

    }

    function _generateDai(address dst, uint256 amount) public {
        // Add Dai to vault
        // collateral to add - wad
        int dink = 0;
        // Normalized Dai to receive - wad
        (, rate,,,) = vat.ilks("ETH-A"); // Retrieve the MakerDAO stability fee
        // collateral to add -- all collateral should already be present
        int dart = -int(amount.divd(rate, ray.unit()));
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
            dart),
            "YToken: vault update failed"
        );
        require(
            daiJoin.exit(address(this), amount),
            "YToken: ETHJOIN failed"
        );
        require(
            dai.transferFrom(source, address(this), amount),
            "YToken: WETH transfer fail"
        );
    }

    /// @dev moves collateral from user into Treasury controlled vault
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