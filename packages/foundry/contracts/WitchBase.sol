// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "./interfaces/DataTypes.sol";
import "./interfaces/ILadle.sol";

contract WitchBase is AccessControl {
    // ==================== Errors ====================

    error VaultAlreadyUnderAuction(bytes12 vaultId, address witch);
    error VaultNotLiquidatable(bytes6 ilkId, bytes6 baseId);
    error AuctionIsCorrect(bytes12 vaultId);
    error AuctioneerRewardTooHigh(uint256 max, uint256 actual);
    error WitchIsDead();
    error CollateralLimitExceeded(uint256 current, uint256 max);
    error NotUnderCollateralised(bytes12 vaultId);
    error UnderCollateralised(bytes12 vaultId);
    error VaultNotUnderAuction(bytes12 vaultId);
    error NotEnoughBought(uint256 expected, uint256 got);
    error JoinNotFound(bytes6 id);
    error UnrecognisedParam(bytes32 param);
    error LeavesDust(uint256 remainder, uint256 min);

    // ==================== User events ====================

    event Auctioned(
        bytes12 indexed vaultId,
        DataTypes.Auction auction,
        uint256 duration,
        uint256 initialCollateralProportion
    );
    event Cancelled(bytes12 indexed vaultId);
    event Cleared(bytes12 indexed vaultId);
    event Ended(bytes12 indexed vaultId);
    event Bought(
        bytes12 indexed vaultId,
        address indexed buyer,
        uint256 ink,
        uint256 art
    );

    // ==================== Governance events ====================

    event Point(
        bytes32 indexed param,
        address indexed oldValue,
        address indexed newValue
    );
    event LineSet(
        bytes6 indexed ilkId,
        bytes6 indexed baseId,
        uint32 duration,
        uint64 vaultProportion,
        uint64 collateralProportion
    );
    event LimitSet(bytes6 indexed ilkId, bytes6 indexed baseId, uint128 max);
    event ProtectedSet(address indexed value, bool protected);
    event AuctioneerRewardSet(uint256 auctioneerReward);

    uint128 public constant ONE_HUNDRED_PERCENT = 1e18;
    uint128 public constant ONE_PERCENT = 0.01e18;

    // Reward given to whomever calls `auction`. It represents a % of the bought collateral
    uint256 public auctioneerReward;
    ILadle public ladle;

    mapping(bytes12 => DataTypes.Auction) public auctions;
    mapping(bytes6 => mapping(bytes6 => DataTypes.Line)) public lines;
    mapping(bytes6 => mapping(bytes6 => DataTypes.Limits)) public limits;
    mapping(address => bool) public protected;

    constructor(ILadle ladle_) public {
        ladle = ladle_;
        auctioneerReward = ONE_HUNDRED_PERCENT;
    }

    // ======================================================================
    // =                        Governance functions                        =
    // ======================================================================

    /// @dev Point to a different ladle
    /// @param param Name of parameter to set (must be "ladle")
    /// @param value Address of new ladle
    function point(bytes32 param, address value) external auth {
        if (param != "ladle") {
            revert UnrecognisedParam(param);
        }
        address oldLadle = address(ladle);
        ladle = ILadle(value);
        emit Point(param, oldLadle, value);
    }

    /// @dev Governance function to set the parameters that govern how much collateral is sold over time.
    /// @param ilkId Id of asset used for collateral
    /// @param baseId Id of asset used for underlying
    /// @param duration Time that auctions take to go to minimal price
    /// @param vaultProportion Vault proportion that is set for auction each time
    /// @param collateralProportion Proportion of collateral that is sold at auction start (1e18 = 100%)
    /// @param max Maximum concurrent auctioned collateral
    function setLineAndLimit(
        bytes6 ilkId,
        bytes6 baseId,
        uint32 duration,
        uint64 vaultProportion,
        uint64 collateralProportion,
        uint128 max
    ) external auth {
        require(
            collateralProportion <= ONE_HUNDRED_PERCENT,
            "Collateral Proportion above 100%"
        );
        require(
            vaultProportion <= ONE_HUNDRED_PERCENT,
            "Vault Proportion above 100%"
        );
        require(
            collateralProportion >= ONE_PERCENT,
            "Collateral Proportion below 1%"
        );
        require(vaultProportion >= ONE_PERCENT, "Vault Proportion below 1%");

        lines[ilkId][baseId] = DataTypes.Line({
            duration: duration,
            vaultProportion: vaultProportion,
            collateralProportion: collateralProportion
        });
        emit LineSet(
            ilkId,
            baseId,
            duration,
            vaultProportion,
            collateralProportion
        );

        limits[ilkId][baseId] = DataTypes.Limits({
            max: max,
            sum: limits[ilkId][baseId].sum // sum is initialized at zero, and doesn't change when changing any ilk parameters
        });
        emit LimitSet(ilkId, baseId, max);
    }

    /// @dev Governance function to protect specific vault owners from liquidations.
    /// @param owner The address that may be set/unset as protected
    /// @param _protected Is this address protected or not
    function setProtected(address owner, bool _protected) external auth {
        protected[owner] = _protected;
        emit ProtectedSet(owner, _protected);
    }

    /// @dev Governance function to set the % paid to whomever starts an auction
    /// @param auctioneerReward_ New % to be used, must have 18 dec precision
    function setAuctioneerReward(uint256 auctioneerReward_) external auth {
        if (auctioneerReward_ > ONE_HUNDRED_PERCENT) {
            revert AuctioneerRewardTooHigh(
                ONE_HUNDRED_PERCENT,
                auctioneerReward_
            );
        }
        auctioneerReward = auctioneerReward_;
        emit AuctioneerRewardSet(auctioneerReward_);
    }
}
