// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "@yield-protocol/vault-interfaces/src/ICauldronGov.sol";
import "@yield-protocol/vault-interfaces/src/IOracle.sol";
import "@yield-protocol/vault-interfaces/src/ILadleGov.sol";
import "@yield-protocol/vault-interfaces/src/IJoin.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";
import {IEmergencyBrake} from "@yield-protocol/utils-v2/contracts/utils/EmergencyBrake.sol";

interface IWitchCustom {
    /// @dev Governance function to set:
    ///  - the auction duration to calculate liquidation prices
    ///  - the proportion of the collateral that will be sold at auction start
    ///  - the maximum collateral that can be auctioned at the same time
    ///  - the minimum collateral that must be left when buying, unless buying all
    ///  - The decimals for maximum and minimum
    function setIlk(
        bytes6 ilkId,
        uint32 duration,
        uint64 initialOffer,
        uint96 line,
        uint24 dust,
        uint8 dec
    ) external;
}

interface IChainlinkMultiOracle {
    function setSource(
        bytes6 baseId,
        IERC20Metadata base,
        bytes6 quoteId,
        IERC20Metadata quote,
        address source
    ) external;
}

/// @dev A wand to add a new collateral.
/// @author @iamsahu
contract CollateralWand is AccessControl {
    bytes4 public constant JOIN = IJoin.join.selector;
    bytes4 public constant EXIT = IJoin.exit.selector;

    ICauldronGov public cauldron;
    ILadleGov public ladle;
    IEmergencyBrake public cloak;
    IChainlinkMultiOracle public chainlinkMultiOracle;
    IWitchCustom public witch;

    struct AuctionLimit {
        bytes6 ilkId;
        uint32 duration;
        uint64 initialOffer;
        uint96 line;
        uint24 dust;
        uint8 dec;
    }

    struct DebtLimit {
        bytes6 baseId;
        bytes6 ilkId;
        uint32 ratio;
        uint96 line;
        uint24 dust;
        uint8 dec;
    }

    struct ChainlinkSource {
        bytes6 baseId;
        address base;
        bytes6 quoteId;
        address quote;
        address source;
    }

    struct SeriesIlk {
        bytes6 series;
        bytes6[] ilkIds;
    }

    constructor(
        ICauldronGov cauldron_,
        ILadleGov ladle_,
        IWitchCustom witch_,
        IEmergencyBrake cloak_,
        IChainlinkMultiOracle chainlinkMultiOracle_
    ) {
        cauldron = cauldron_;
        ladle = ladle_;
        witch = witch_;
        cloak = cloak_;
        chainlinkMultiOracle = chainlinkMultiOracle_;
    }

    /// @notice Function to add a chainlink collateral
    /// @param assetId assetId of the collateral being added
    /// @param assetAddress address of the collateral
    /// @param joinAddress address of the join for the asset
    /// @param deployer address of the deployer
    /// @param chainlinkSources address of the chainlink sources
    /// @param auctionLimits auction limits for the asset
    /// @param debtLimits debt limits for the asset
    /// @param seriesIlks seriesIlk data to which the asset is to be added
    function addChainlinkCollateral(
        bytes6 assetId,
        address assetAddress,
        address joinAddress,
        address deployer,
        ChainlinkSource[] calldata chainlinkSources,
        AuctionLimit[] calldata auctionLimits,
        DebtLimit[] calldata debtLimits,
        SeriesIlk[] calldata seriesIlks
    ) external auth {
        orchestrateJoin(joinAddress, deployer);
        addAsset(assetId, assetAddress, joinAddress);
        for (uint256 index = 0; index < chainlinkSources.length; index++) {
            ChainlinkSource memory chainlinksource = chainlinkSources[index];
            updateChainLinkSource(
                chainlinksource.baseId,
                chainlinksource.base,
                chainlinksource.quoteId,
                chainlinksource.quote,
                chainlinksource.source
            );
        }

        makeIlk(joinAddress, auctionLimits, debtLimits);

        addIlksToSeries(seriesIlks);
    }

    /// @notice Orchestrate the join to grant & revoke the correct permissions
    /// @param joinAddress address of the join to be orchestrated
    /// @param deployer address of the deployer
    function orchestrateJoin(address joinAddress, address deployer) internal {
        AccessControl joinAccessControl = AccessControl(joinAddress);

        // revoke role of deployer
        joinAccessControl.revokeRole(ROOT, deployer);
        // grant ROOT to cloak
        joinAccessControl.grantRole(ROOT, address(cloak));
        // cloak plan
        bytes4[] memory sigs = new bytes4[](2);
        sigs[0] = JOIN;
        sigs[1] = EXIT;

        IEmergencyBrake.Permission[] memory permissions = new IEmergencyBrake.Permission[](1);
        permissions[0] = IEmergencyBrake.Permission(joinAddress, sigs);
        cloak.plan(address(ladle), permissions);
    }

    /// @notice Function to update CompositeSource
    /// @param baseId id of the base asset
    /// @param quoteId id of the quote asset
    /// @param source address of the oracle for baseId/quoteId
    function updateCompositeSource(
        bytes6 baseId,
        bytes6 quoteId,
        IOracle source
    ) internal {}

    /// @notice Function to update CompositePaths
    /// @param baseId id of the base asset
    /// @param quoteId id of the quote asset
    /// @param sources sources of the oracle
    function updateCompositePath(
        bytes6 baseId,
        bytes6 quoteId,
        IOracle[] calldata sources
    ) internal {}

    /// @notice Function to update ChainlinkSource for the supplied baseId/quoteId
    /// @param baseId baseId
    /// @param base address of the base asset
    /// @param quoteId quoteId
    /// @param quote address of the quote asset
    /// @param source address of the oracle for baseId/quoteId
    function updateChainLinkSource(
        bytes6 baseId,
        address base,
        bytes6 quoteId,
        address quote,
        address source
    ) internal {
        // set sources for chainlink
        chainlinkMultiOracle.setSource(baseId, IERC20Metadata(base), quoteId, IERC20Metadata(quote), source);
    }

    /// @notice Function to add asset to the cauldron & join to the ladle
    /// @param assetId Id for the asset being added
    /// @param assetAddress Address of the asset being added
    /// @param joinAddress Address of the join for the asset
    function addAsset(
        bytes6 assetId,
        address assetAddress,
        address joinAddress
    ) internal {
        // add asset to cauldron
        cauldron.addAsset(assetId, assetAddress);
        // Allow Ladle to join and exit on the asset Join
        bytes4[] memory sigs = new bytes4[](2);
        sigs[0] = JOIN;
        sigs[1] = EXIT;
        AccessControl(joinAddress).grantRoles(sigs, address(ladle));
        // Register the Join in the Ladle
        ladle.addJoin(assetId, joinAddress);
    }

    /// @notice Makes the asset into an ilk by setting up auction & debt limits
    /// @param joinAddress address of the join of the ilk
    /// @param auctionLimits auction limits for the ilks
    /// @param debtLimits debt limits for the ilks against bases
    function makeIlk(
        address joinAddress,
        AuctionLimit[] memory auctionLimits,
        DebtLimit[] memory debtLimits
    ) internal {
        // Configure auction limits for the ilk on the witch
        for (uint256 index = 0; index < auctionLimits.length; index++) {
            AuctionLimit memory auctionLimit = auctionLimits[index];
            updateAuctionLimit(
                auctionLimit.ilkId,
                auctionLimit.duration,
                auctionLimit.initialOffer,
                auctionLimit.line,
                auctionLimit.dust,
                auctionLimit.dec
            );
        }
        // Allow Witch to exit ilk
        AccessControl joinAccessControl = AccessControl(joinAddress);
        joinAccessControl.grantRole(EXIT, address(witch));
        // Log a plan to undo the orchestration above in emergencies
        bytes4[] memory sigs = new bytes4[](1);
        sigs[0] = EXIT;

        IEmergencyBrake.Permission[] memory permissions = new IEmergencyBrake.Permission[](1);
        permissions[0] = IEmergencyBrake.Permission(joinAddress, sigs);
        cloak.plan(address(witch), permissions);

        for (uint256 index = 0; index < debtLimits.length; index++) {
            DebtLimit memory debtLimit = debtLimits[index];
            updateDebtLimit(
                debtLimit.baseId,
                debtLimit.ilkId,
                debtLimit.ratio,
                debtLimit.line,
                debtLimit.dust,
                debtLimit.dec
            );
        }
    }

    /// @dev Function to set the auction limit on the witch
    /// @param ilkId Id of the ilk
    /// @param duration the auction duration to calculate liquidation prices
    /// @param initialOffer the proportion of the collateral that will be sold at auction start
    /// @param line the maximum collateral that can be auctioned at the same time
    /// @param dust the minimum collateral that must be left when buying, unless buying all
    /// @param dec The decimals for maximum and minimum
    function updateAuctionLimit(
        bytes6 ilkId,
        uint32 duration,
        uint64 initialOffer,
        uint96 line,
        uint24 dust,
        uint8 dec
    ) internal {
        witch.setIlk(ilkId, duration, initialOffer, line, dust, dec);
    }

    /// @dev Set the maximum and minimum debt for an underlying and ilk pair. Can be reset.
    /// @param baseId asset identifier (bytes6 tag)
    /// @param ilkId asset identifier (bytes6 tag)
    /// @param ratio ratio as a fixed point number with 6 decimals
    /// @param line ceiling, modified by decimals
    /// @param dust vault debt, modified by decimals
    /// @param dec to append to debt ceiling and minimum vault debt.
    function updateDebtLimit(
        bytes6 baseId,
        bytes6 ilkId,
        uint32 ratio,
        uint96 line,
        uint24 dust,
        uint8 dec
    ) internal {
        cauldron.setSpotOracle(baseId, ilkId, IOracle(address(chainlinkMultiOracle)), ratio);
        cauldron.setDebtLimits(baseId, ilkId, line, dust, dec);
    }

    /// @notice Ilks to accept for series
    /// @param seriesIlks series & ilks to be added
    function addIlksToSeries(SeriesIlk[] calldata seriesIlks) internal {
        // Add ilks to the series
        for (uint256 index = 0; index < seriesIlks.length; index++) {
            SeriesIlk memory seriesIlk = seriesIlks[index];
            cauldron.addIlks(seriesIlk.series, seriesIlk.ilkIds);
        }
    }
}
