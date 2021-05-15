// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./Join.sol";
import "./FYToken.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";

interface ICauldron {
    function assets(bytes6) external view returns (address);
    function addAsset(bytes6, address) external;
    function addSeries(bytes6, bytes6, address) external;
    function addIlks(bytes6, bytes6[] memory) external;
    function setRateOracle(bytes6, address) external;
    function setSpotOracle(bytes6, bytes6, address, uint32) external;
    function setMaxDebt(bytes6, bytes6, uint128) external;
}

interface ILadle {
    function joins(bytes6) external view returns (Join);
    function addJoin(bytes6, address) external;
    function addPool(bytes6, address) external;
}

interface IPoolFactory {
  function calculatePoolAddress(address, address) external view returns (address);
  function createPool(address, address) external view returns (address);
}

interface ISpotMultiOracle {
    function setSource(bytes6, bytes6, address) external;
}

interface IRateMultiOracle {
    function setSource(bytes6, bytes32, address) external;
}

interface IChiMultiOracle {
    function setSource(bytes6, bytes32, address) external;
}

/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient governance features.
contract Wand is AccessControl {

    ICauldron public immutable cauldron;
    ILadle public immutable ladle;
    IPoolFactory public immutable poolFactory;

    constructor (ICauldron cauldron_, ILadle ladle_, IPoolFactory poolFactory_) {
        cauldron = cauldron_;
        ladle = ladle_;
        poolFactory = poolFactory_;
    }

    /// @dev Return a function signature
    function id(bytes memory signature) public pure returns (bytes4) {
        return bytes4(keccak256(signature));
    }

    /// @dev Add an existing asset to the protocol, meaning:
    ///  - Add the asset to the cauldron
    ///  - Deploy a new Join, and integrate it with the Ladle
    ///  - If the asset is a base, integrate its rate source
    ///  - If the asset is a base, integrate a spot source and set a debt ceiling for any provided ilks
    function addAsset(
        bytes6 assetId,
        address asset,
        address rateOracle,
        address rateSource,
        bytes6[] memory ilkIds,
        address[] memory spotOracles,
        address[] memory spotSources,
        uint32[] memory ratios,
        uint128[] memory maxDebts
    ) public auth {
        // TODO: Check inputs
        // Add asset to cauldron, deploy new Join, and add it to the ladle
        cauldron.addAsset(assetId, asset);
        Join join = new Join(asset);
        bytes4[] memory sigs = new bytes4[](2);
        sigs[0] = id("join(address,uint128)");
        sigs[1] = id("exit(address,uint128)");
        join.grantRoles(sigs, address(ladle));
        ladle.addJoin(assetId, address(join));
        
        // If the asset will be a base, add the rate source to the rate oracle, and the rate oracle to the cauldron
        if (rateOracle != address(0)) {
            IRateMultiOracle(rateOracle).setSource(assetId, "RATE", rateSource);
            cauldron.setRateOracle(assetId, rateOracle);
        }

        // If the asset will be a base, add spot oracles and debt ceilings for any provided ilks
        for (uint256 i = 0; i <= ilkIds.length; i += 1) {
            ISpotMultiOracle(spotOracles[i]).setSource(assetId, ilkIds[i], spotSources[i]);
            cauldron.setSpotOracle(assetId, ilkIds[i], spotOracles[i], ratios[i]);
            cauldron.setMaxDebt(assetId, ilkIds[i], maxDebts[i]);
        }
    }

    /// @dev Add an existing series to the protocol, meaning:
    ///  - Add the asset to the cauldron
    ///  - Deploy a new Join, and integrate it with the Ladle
    ///  - If the asset is a base, integrate its rate source
    ///  - If the asset is a base, integrate a spot source and set a debt ceiling for any provided ilks
    function addSeries(
        bytes6 seriesId,
        bytes6 baseId,
        uint32 maturity,
        address chiOracle,
        address chiSource,
        bytes6[] memory ilkIds,
        string memory name,
        string memory symbol
    ) public auth {
        // TODO: Check inputs
        address base = cauldron.assets(baseId);
        Join baseJoin = ladle.joins(baseId);
        
        // If provided, add the chi source to the chi oracle, and the chi oracle to the cauldron
        if (chiSource != address(0)) {
            IChiMultiOracle(chiOracle).setSource(baseId, "CHI", chiSource);
            cauldron.setRateOracle(baseId, chiOracle);
        }

        FYToken fyToken = new FYToken(
            baseId,
            IOracle(chiOracle),
            baseJoin,
            maturity,
            name,     // Derive from base and maturity, perhaps
            symbol    // Derive from base and maturity, perhaps
        );

        // Allow the fyToken to pull from the base join for redemption
        bytes4[] memory sigs = new bytes4[](1);
        sigs[1] = id("exit(address,uint128)");
        baseJoin.grantRoles(sigs, address(ladle));

        // Allow the ladle to issue and cancel fyToken
        sigs = new bytes4[](2);
        sigs[1] = id("mint(address,uint256)");
        sigs[2] = id("burn(address,uint256)");
        fyToken.grantRoles(sigs, address(ladle));

        // Add fyToken/series to the Cauldron and all ilks to each series
        cauldron.addSeries(seriesId, baseId, address(fyToken));
        cauldron.addIlks(seriesId, ilkIds);

        // Create the pool for the base and fyToken
        address pool = poolFactory.createPool(address(base), address(fyToken)); // TODO: Remember to hand ownership to governor
        ladle.addPool(seriesId, pool);
    }
}