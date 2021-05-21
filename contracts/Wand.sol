// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/vault-interfaces/IJoinFactory.sol";
import "@yield-protocol/vault-interfaces/IJoin.sol";
import "@yield-protocol/vault-interfaces/DataTypes.sol";
import "@yield-protocol/yieldspace-interfaces/IPoolFactory.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "./FYToken.sol";


interface ICauldronGov {
    function assets(bytes6) external view returns (address);
    function series(bytes6) external view returns (DataTypes.Series memory);
    function rateOracles(bytes6) external view returns (IOracle);
    function addAsset(bytes6, address) external;
    function addSeries(bytes6, bytes6, IFYToken) external;
    function addIlks(bytes6, bytes6[] memory) external;
    function setRateOracle(bytes6, IOracle) external;
    function setSpotOracle(bytes6, bytes6, IOracle, uint32) external;
    function setDebtLimits(bytes6, bytes6, uint96, uint24, uint8) external;
}

interface ILadleGov {
    function joins(bytes6) external view returns (IJoin);
    function addJoin(bytes6, address) external;
    function addPool(bytes6, address) external;
}

interface IRateMultiOracleGov {
    function setSource(bytes6, bytes32, address) external;
}

interface ISpotMultiOracleGov {
    function setSource(bytes6, bytes6, address) external;
}

interface IOwnable {
    function transferOwnership(address) external;
}

/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient governance features.
contract Wand is AccessControl {

    bytes4 public constant JOIN = bytes4(keccak256("join(address,uint128)"));
    bytes4 public constant EXIT = bytes4(keccak256("exit(address,uint128)"));
    bytes4 public constant MINT = bytes4(keccak256("mint(address,uint256)"));
    bytes4 public constant BURN = bytes4(keccak256("burn(address,uint256)"));
    

    ICauldronGov public immutable cauldron;
    ILadleGov public immutable ladle;
    IPoolFactory public immutable poolFactory;
    IJoinFactory public immutable joinFactory;

    constructor (ICauldronGov cauldron_, ILadleGov ladle_, IPoolFactory poolFactory_, IJoinFactory joinFactory_) {
        cauldron = cauldron_;
        ladle = ladle_;
        poolFactory = poolFactory_;
        joinFactory = joinFactory_;
    }

    /// @dev Add an existing asset to the protocol, meaning:
    ///  - Add the asset to the cauldron
    ///  - Deploy a new Join, and integrate it with the Ladle
    ///  - If the asset is a base, integrate its rate source
    ///  - If the asset is a base, integrate a spot source and set a debt ceiling for any provided ilks
    function addAsset(
        bytes6 assetId,
        address asset
    ) public auth {
        // Add asset to cauldron, deploy new Join, and add it to the ladle
        require (address(asset) != address(0), "Asset required");
        cauldron.addAsset(assetId, asset);
        AccessControl join = AccessControl(joinFactory.createJoin(asset));  // We need the access control methods of Join
        bytes4[] memory sigs = new bytes4[](2);
        sigs[0] = JOIN;
        sigs[1] = EXIT;
        join.grantRoles(sigs, address(ladle));
        join.grantRole(join.ROOT(), msg.sender);
        // join.renounceRole(join.ROOT(), address(this));  // If Wand gives up ownership it can't create fyToken
        ladle.addJoin(assetId, address(join));
    }

    /// @dev Make a base asset out of a generic asset, by adding rate and chi oracles.
    /// This assumes CompoundMultiOracles, which deliver both rate and chi.
    function makeBase(bytes6 assetId, IRateMultiOracleGov oracle, address rateSource, address chiSource) public auth {
        require (address(oracle) != address(0), "Oracle required");
        require (rateSource != address(0), "Rate source required");
        require (chiSource != address(0), "Chi source required");

        oracle.setSource(assetId, "rate", rateSource);
        oracle.setSource(assetId, "chi", chiSource);
        cauldron.setRateOracle(assetId, IOracle(address(oracle))); // TODO: Consider adding a registry of chi oracles in cauldron as well
    }

    /// @dev Make an ilk asset out of a generic asset, by adding a spot oracle against a base asset, collateralization ratio, and debt ceiling.
    function makeIlk(bytes6 baseId, bytes6 ilkId, ISpotMultiOracleGov oracle, address spotSource, uint32 ratio, uint96 max, uint24 min, uint8 dec) public auth {
        oracle.setSource(baseId, ilkId, spotSource);
        cauldron.setSpotOracle(baseId, ilkId, IOracle(address(oracle)), ratio);
        cauldron.setDebtLimits(baseId, ilkId, max, min, dec);
    }

    /// @dev Add an existing series to the protocol, by deploying a FYToken, and registering it in the cauldron with the approved ilks
    /// This must be followed by a call to addPool
    function addSeries(
        bytes6 seriesId,
        bytes6 baseId,
        uint32 maturity,
        bytes6[] memory ilkIds,
        string memory name,
        string memory symbol
    ) public auth {
        address base = cauldron.assets(baseId);
        require(base != address(0), "Base not found");

        IJoin baseJoin = ladle.joins(baseId);
        require(address(baseJoin) != address(0), "Join not found");

        IOracle oracle = cauldron.rateOracles(baseId);
        require(address(oracle) != address(0), "Chi oracle not found");

        FYToken fyToken = new FYToken(
            baseId,
            oracle,
            baseJoin,
            maturity,
            name,     // Derive from base and maturity, perhaps
            symbol    // Derive from base and maturity, perhaps
        ); // TODO: Use a FYTokenFactory to make Wand deployable at 20000 runs

        // Allow the fyToken to pull from the base join for redemption
        bytes4[] memory sigs = new bytes4[](1);
        sigs[0] = EXIT;
        AccessControl(address(baseJoin)).grantRoles(sigs, address(ladle));

        // Allow the ladle to issue and cancel fyToken
        sigs = new bytes4[](2);
        sigs[0] = MINT;
        sigs[1] = BURN;
        fyToken.grantRoles(sigs, address(ladle));

        // Pass ownership of the fyToken to msg.sender
        fyToken.grantRole(fyToken.ROOT(), msg.sender);
        fyToken.renounceRole(fyToken.ROOT(), address(this));

        // Add fyToken/series to the Cauldron and approve ilks for the series
        cauldron.addSeries(seriesId, baseId, fyToken);
        cauldron.addIlks(seriesId, ilkIds);

        // Create the pool for the base and fyToken
        poolFactory.createPool(base, address(fyToken));
        IOwnable pool = IOwnable(poolFactory.calculatePoolAddress(base, address(fyToken)));
        

        // Pass ownership of pool to msg.sender
        pool.transferOwnership(msg.sender);

        // Register pool in Ladle
        ladle.addPool(seriesId, address(pool));
    }
}