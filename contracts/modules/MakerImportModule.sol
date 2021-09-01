// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import "@yield-protocol/vault-interfaces/ICauldron.sol";
import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "@yield-protocol/vault-interfaces/DataTypes.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256U128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU256I128.sol";
import "@yield-protocol/utils-v2/contracts/cast/CastU128I128.sol";
import "@yield-protocol/utils-v2/contracts/math/WMul.sol";
import "@yield-protocol/utils-v2/contracts/math/WMulUp.sol";
import "../LadleStorage.sol";

/// @dev interface for the DssCdpManager contract from MakerDAO
interface ICDPMgr {
    function vat() external view returns(address);
    function owns(uint256 cdp) external view returns(address);
    function urns(uint256 cdp) external view returns(address);
    function ilks(uint256 cdp) external view returns(bytes32);
    function cdpCan(address owner, uint256 cdp, address usr) external view returns(uint256);
    function cdpAllow(uint256 cdp, address usr, uint256 ok) external;
    function give(uint256 cdp, address usr) external;
    function frob(uint256 cdp, int dink, int dart) external;
    function flux(uint256 cdp, address dst, uint256 wad) external;
    function move(uint256 cdp, address dst, uint256 rad) external;
}

interface IProxyRegistry {
    function proxies(address) external view returns (address);
}

interface IIlkRegistry { // https://github.com/makerdao/ilk-registry
    function info(bytes32 ilk) external view returns (
        string memory name,
        string memory symbol,
        uint256 class,
        uint256 dec,
        address gem,
        address pip,
        address join,
        address xlip
    );
}

interface IMakerJoin {
    function join(address usr, uint256 WAD) external;
    function exit(address usr, uint256 WAD) external;
}

interface IDaiJoin {
    function dai() external view returns (address);
}

interface IVat {
    function ilks(bytes32) external view returns (uint256, uint256, uint256, uint256, uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
}

/// ATTENTION: THIS MODULE IS A DRAFT AND IT IS NOT TO BE DEPLOYED UNTIL TESTED
contract MakerImportModule is LadleStorage {
    using CastU256U128 for uint256;
    using CastU256I128 for uint256;
    using CastU128I128 for uint128;
    using WMul for uint256;
    using WMulUp for uint256;

    event ImportedFromMaker(bytes12 indexed vaultId, uint256 indexed cdp, uint256 ilkAmount, uint256 daiDebt);

    // The MakerImportModule inherits the same storage layout as the Ladle.
    // When the Ladle delegatecalls into the MakerImportModule, the functions called have access to the Ladle storage.
    // The following variables are avaiable to delegatecalls, being immutable
    IVat public immutable vat;
    IERC20 public immutable dai;    
    IMakerJoin public immutable makerDaiJoin;
    ICDPMgr public immutable cdpMgr;
    IProxyRegistry public immutable proxyRegistry;
    IIlkRegistry public immutable ilkRegistry;

    // The MakerImportModule doesn't have any data storage of its own

    constructor (ICauldron cauldron_, IWETH9 weth_, IMakerJoin makerDaiJoin_, ICDPMgr cdpMgr_, IProxyRegistry proxyRegistry_, IIlkRegistry ilkRegistry_) 
        LadleStorage(cauldron_, weth_) {
        proxyRegistry = proxyRegistry_;
        ilkRegistry = ilkRegistry_;
        cdpMgr = cdpMgr_;
        vat = IVat(cdpMgr_.vat());
        makerDaiJoin = makerDaiJoin_;
        IERC20 dai_ = dai = IERC20(IDaiJoin(address(makerDaiJoin_)).dai());
        dai_.approve(address(makerDaiJoin_), type(uint256).max); // TODO: daiJoin.hope as well?
    }

    /// @dev Obtains a vault by vaultId from the Cauldron, and verifies that msg.sender is the owner
    function getOwnedVault(bytes12 vaultId)
        internal view returns(DataTypes.Vault memory vault)
    {
        vault = cauldron.vaults(vaultId);
        require (vault.owner == msg.sender, "Only vault owner");
    }

    /// @dev Obtains a series by seriesId from the Cauldron, and verifies that it exists
    function getSeries(bytes6 seriesId)
        internal view returns(DataTypes.Series memory series)
    {
        series = cauldron.series(seriesId);
        require (series.fyToken != IFYToken(address(0)), "Series not found");
    }

    /// @dev Obtains a join by assetId, and verifies that it exists
    function getJoin(bytes6 assetId)
        internal view returns(IJoin join)
    {
        join = joins[assetId];
        require (join != IJoin(address(0)), "Join not found");
    }

    /// @dev Obtains a pool by seriesId, and verifies that it exists
    function getPool(bytes6 seriesId)
        internal view returns(IPool pool)
    {
        pool = pools[seriesId];
        require (pool != IPool(address(0)), "Pool not found");
    }

    /// @dev Add collateral and borrow from vault, pull assets from and push borrowed asset to user
    /// Or, repay to vault and remove collateral, pull borrowed asset from and push assets to user
    function _pour(bytes12 vaultId, DataTypes.Vault memory vault, address to, int128 ink, int128 art)
        private
        returns (DataTypes.Balances memory balances)
    {
        DataTypes.Series memory series;
        if (art != 0) series = getSeries(vault.seriesId);

        int128 fee;
        if (art > 0) fee = ((series.maturity - block.timestamp) * uint256(int256(art)).wmul(borrowingFee)).i128();

        // Update accounting
        balances = cauldron.pour(vaultId, ink, art + fee);

        // Manage collateral
        if (ink != 0) {
            IJoin ilkJoin = getJoin(vault.ilkId);
            if (ink > 0) ilkJoin.join(vault.owner, uint128(ink));
            if (ink < 0) ilkJoin.exit(to, uint128(-ink));
        }

        // Manage debt tokens
        if (art != 0) {
            if (art > 0) series.fyToken.mint(to, uint128(art));
            else series.fyToken.burn(msg.sender, uint128(-art));
        }
    }

    /// @dev Migrate part of a CDPMgr-controlled MakerDAO vault to Yield.
    function importCdpPosition(bytes12 vaultId, uint256 cdp, uint128 ilkAmount, uint128 debtAmount, uint128 maxDaiPrice) public {
        // Authenticate user
        DataTypes.Vault memory vault = getOwnedVault(vaultId);
        address cdpOwner = cdpMgr.owns(cdp);
        
        require(
            cdpOwner == msg.sender ||                           // CDP owned by the user
            cdpOwner == proxyRegistry.proxies(msg.sender),      // CDP owned by the user's dsproxy
            "Only CDP owner or its dsproxy"
        );

        // Grab CDP
        cdpMgr.give(cdp, address(this));

        // Transfer position
        _importCdpPosition(vaultId, vault, cdp, ilkAmount, debtAmount, maxDaiPrice);
        
        // Return rest of CDP
        cdpMgr.give(cdp, cdpOwner);
    }

    /// @dev Migrate a CDPMgr-controlled MakerDAO vault to Yield.
    function importCdp(bytes12 vaultId, uint256 cdp, uint128 maxDaiPrice) public {
        // Authenticate user
        DataTypes.Vault memory vault = getOwnedVault(vaultId);
        address cdpOwner = cdpMgr.owns(cdp);
        
        require(
            cdpOwner == msg.sender ||                           // CDP owned by the user
            cdpOwner == proxyRegistry.proxies(msg.sender),      // CDP owned by the user's dsproxy
            "Only CDP owner or its dsproxy"
        );

        // Grab CDP
        cdpMgr.give(cdp, address(this));

        // Transfer position
        bytes32 ilk = cdpMgr.ilks(cdp);
        (uint256 ink, uint256 art) = vat.urns(ilk, cdpMgr.urns(cdp));
        _importCdpPosition(vaultId, vault, cdp, ink.u128(), art.u128(), maxDaiPrice);
        
        // Return empty CDP
        cdpMgr.give(cdp, cdpOwner);
    }

    /// @dev Transfer debt and collateral from MakerDAO (this contract's CDP) to Yield (user's vault)
    function _importCdpPosition(bytes12 vaultId, DataTypes.Vault memory vault, uint256 cdp, uint128 ilkAmount, uint128 debtAmount, uint128 maxDaiPrice) public {
        // The user specifies the fyDai he wants to mint to cover his maker debt, the weth to be passed on as collateral, and the dai debt to move
        bytes32 ilk = cdpMgr.ilks(cdp);
        (uint256 ink, uint256 art) = vat.urns(ilk, cdpMgr.urns(cdp));
        
        require(
            debtAmount <= art,
            "Not enough debt in Maker"
        );
        require(
            ilkAmount <= ink,
            "Not enough collateral in Maker"
        );

        IPool pool = getPool(vault.seriesId);

        // Find cost in fyDai
        (, uint256 rate,,,) = vat.ilks(ilk);
        uint128 daiNeeded = uint256(debtAmount).wmulup(rate).u128();
        uint128 fyDaiAmount = pool.buyBasePreview(daiNeeded);

        {
            // Mint fyToken to the pool, as a kind of flash loan
            IFYToken(pool.fyToken()).mint(address(pool), fyDaiAmount);

            // Pool should take exactly all fyDai minted. ImportCdpProxy will hold the dai temporarily
            pool.buyBase(address(this), daiNeeded, maxDaiPrice);

            makerDaiJoin.join(cdpMgr.urns(cdp), daiNeeded);         // Put the Dai in Maker
            cdpMgr.frob(                                            // Pay the debt and unlock collateral in Maker
                cdp,
                -ilkAmount.i128(),                                  // Removing Collateral
                -debtAmount.i128()                                  // Removing Dai debt
            );
            cdpMgr.flux(cdp, address(this), ilkAmount);

            (,,,,,, address makerIlkJoin,) = ilkRegistry.info(ilk);
            IMakerJoin(makerIlkJoin).exit(address(getJoin(vault.ilkId)), ilkAmount);     // TODO: ilkJoin.hope as well?
        }
        
        _pour(vaultId, vault, msg.sender, ilkAmount.i128(), fyDaiAmount.i128());         // Add the collateral to Yield

        emit ImportedFromMaker(vaultId, cdp, ilkAmount, daiNeeded);
    }
}