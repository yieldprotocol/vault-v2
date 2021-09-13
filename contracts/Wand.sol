// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import "@yield-protocol/vault-interfaces/ICauldronGov.sol";
import "@yield-protocol/vault-interfaces/ILadleGov.sol";
// import "@yield-protocol/vault-interfaces/IWitchGov.sol";
import "@yield-protocol/vault-interfaces/IMultiOracleGov.sol";
import "@yield-protocol/vault-interfaces/IJoinFactory.sol";
import "@yield-protocol/vault-interfaces/IJoin.sol";
import "@yield-protocol/vault-interfaces/IFYTokenFactory.sol";
import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "@yield-protocol/vault-interfaces/DataTypes.sol";
import "@yield-protocol/yieldspace-interfaces/IPoolFactory.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "./constants/Constants.sol";

interface IWitchGov {
    function ilks(bytes6) external view returns(bool, uint32, uint64, uint128);
}

/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient governance features.
contract Wand is AccessControl, Constants {

    event Point(bytes32 indexed param, address value);

    bytes4 public constant JOIN = IJoin.join.selector;      // bytes4(keccak256("join(address,uint128)"));
    bytes4 public constant EXIT = IJoin.exit.selector;      // bytes4(keccak256("exit(address,uint128)"));
    bytes4 public constant MINT = IFYToken.mint.selector;   // bytes4(keccak256("mint(address,uint256)"));
    bytes4 public constant BURN = IFYToken.burn.selector;   // bytes4(keccak256("burn(address,uint256)"));

    ICauldronGov public cauldron;
    ILadleGov public ladle;
    IWitchGov public witch;
    IPoolFactory public poolFactory;
    IJoinFactory public joinFactory;
    IFYTokenFactory public fyTokenFactory;

    constructor (
        ICauldronGov cauldron_,
        ILadleGov ladle_,
        IWitchGov witch_,
        IPoolFactory poolFactory_,
        IJoinFactory joinFactory_,
        IFYTokenFactory fyTokenFactory_
    ) {
        cauldron = cauldron_;
        ladle = ladle_;
        witch = witch_;
        poolFactory = poolFactory_;
        joinFactory = joinFactory_;
        fyTokenFactory = fyTokenFactory_;
    }

    /// @dev Point to a different cauldron, ladle, witch, poolFactory, joinFactory or fyTokenFactory
    function point(bytes32 param, address value) external auth {
        if (param == "cauldron") cauldron = ICauldronGov(value);
        else if (param == "ladle") ladle = ILadleGov(value);
        else if (param == "witch") witch = IWitchGov(value);
        else if (param == "poolFactory") poolFactory = IPoolFactory(value);
        else if (param == "joinFactory") joinFactory = IJoinFactory(value);
        else if (param == "fyTokenFactory") fyTokenFactory = IFYTokenFactory(value);
        else revert("Unrecognized parameter");
        emit Point(param, value);
    }

    /// @dev Add an existing asset to the protocol, meaning:
    ///  - Add the asset to the cauldron
    ///  - Deploy a new Join, and integrate it with the Ladle
    ///  - If the asset is a base, integrate its rate source
    ///  - If the asset is a base, integrate a spot source and set a debt ceiling for any provided ilks
    function addAsset(
        bytes6 assetId,
        address asset
    ) external auth {
        // Add asset to cauldron, deploy new Join, and add it to the ladle
        require (address(asset) != address(0), "Asset required");
        cauldron.addAsset(assetId, asset);
        AccessControl join = AccessControl(joinFactory.createJoin(asset));  // We need the access control methods of Join
        bytes4[] memory sigs = new bytes4[](2);
        sigs[0] = JOIN;
        sigs[1] = EXIT;
        join.grantRoles(sigs, address(ladle));
        join.grantRole(ROOT, msg.sender);
        // join.renounceRole(ROOT, address(this));  // Wand requires ongoing rights to set up permissions to joins
        ladle.addJoin(assetId, address(join));
    }

    /// @dev Make a base asset out of a generic asset.
    /// @notice `oracle` must be able to deliver a value for assetId and 'rate'
    function makeBase(bytes6 assetId, IMultiOracleGov oracle) external auth {
        require (address(oracle) != address(0), "Oracle required");

        cauldron.setLendingOracle(assetId, IOracle(address(oracle)));
        
        AccessControl baseJoin = AccessControl(address(ladle.joins(assetId)));
        baseJoin.grantRole(JOIN, address(witch)); // Give the Witch permission to join base
    }

    /// @dev Make an ilk asset out of a generic asset.
    /// @notice `oracle` must be able to deliver a value for baseId and ilkId
    function makeIlk(bytes6 baseId, bytes6 ilkId, IMultiOracleGov oracle, uint32 ratio, uint96 max, uint24 min, uint8 dec) external auth {
        require (address(oracle) != address(0), "Oracle required");
        (bool ilkInitialized,,,) = witch.ilks(ilkId);
        require (ilkInitialized == true, "Initialize ilk in Witch");
        cauldron.setSpotOracle(baseId, ilkId, IOracle(address(oracle)), ratio);
        cauldron.setDebtLimits(baseId, ilkId, max, min, dec);

        AccessControl ilkJoin = AccessControl(address(ladle.joins(ilkId)));
        ilkJoin.grantRole(EXIT, address(witch)); // Give the Witch permission to exit ilk
    }

    /// @dev Add an existing series to the protocol, by deploying a FYToken, and registering it in the cauldron with the approved ilks
    /// This must be followed by a call to addPool
    function addSeries(
        bytes6 seriesId,
        bytes6 baseId,
        uint32 maturity,
        bytes6[] calldata ilkIds,
        string memory name,
        string memory symbol
    ) external auth {
        address base = cauldron.assets(baseId);
        require(base != address(0), "Base not found");

        IJoin baseJoin = ladle.joins(baseId);
        require(address(baseJoin) != address(0), "Join not found");

        IOracle oracle = cauldron.lendingOracles(baseId); // The lending oracles in the Cauldron are also configured to return chi
        require(address(oracle) != address(0), "Chi oracle not found");

        AccessControl fyToken = AccessControl(fyTokenFactory.createFYToken(
            baseId,
            oracle,
            baseJoin,
            maturity,
            name,     // Derive from base and maturity, perhaps
            symbol    // Derive from base and maturity, perhaps
        ));

        // Allow the fyToken to pull from the base join for redemption
        bytes4[] memory sigs = new bytes4[](1);
        sigs[0] = EXIT;
        AccessControl(address(baseJoin)).grantRoles(sigs, address(fyToken));

        // Allow the ladle to issue and cancel fyToken
        sigs = new bytes4[](2);
        sigs[0] = MINT;
        sigs[1] = BURN;
        fyToken.grantRoles(sigs, address(ladle));

        // Pass ownership of the fyToken to msg.sender
        fyToken.grantRole(ROOT, msg.sender);
        fyToken.renounceRole(ROOT, address(this));

        // Add fyToken/series to the Cauldron and approve ilks for the series
        cauldron.addSeries(seriesId, baseId, IFYToken(address(fyToken)));
        cauldron.addIlks(seriesId, ilkIds);

        // Create the pool for the base and fyToken
        poolFactory.createPool(base, address(fyToken));
        address pool = poolFactory.calculatePoolAddress(base, address(fyToken));

        // Register pool in Ladle
        ladle.addPool(seriesId, address(pool));
    }
}