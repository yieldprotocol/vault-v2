// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.14;
import "@yield-protocol/vault-interfaces/src/ICauldronGov.sol";
import "@yield-protocol/vault-interfaces/src/ILadleGov.sol";
import "@yield-protocol/vault-interfaces/src/IJoin.sol";
import "@yield-protocol/vault-interfaces/src/IFYToken.sol";
import "@yield-protocol/yieldspace-v2/contracts/Pool.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "./FYToken.sol";

/// @dev A wand to create new series.
contract SeriesWand is AccessControl {
    bytes4 public constant JOIN = IJoin.join.selector;
    bytes4 public constant EXIT = IJoin.exit.selector;
    bytes4 public constant MINT = IFYToken.mint.selector;
    bytes4 public constant BURN = IFYToken.burn.selector;

    ICauldronGov public cauldron;
    ILadleGov public ladle;

    constructor(ICauldronGov cauldron_, ILadleGov ladle_) {
        cauldron = cauldron_;
        ladle = ladle_;
    }

    /// @dev Add a series to the protocol, by deploying a FYToken, and registering it in the cauldron with the approved ilks
    /// @param seriesId The id for the series
    /// @param baseId The id of the base Token
    /// @param ilkIds The ilk for the fyToken
    /// @param fyToken fytoken for the series
    /// @param pool address of the pool for the series
    function addSeries(
        bytes6 seriesId,
        bytes6 baseId,
        bytes6[] calldata ilkIds,
        IFYToken fyToken,
        address pool
    ) external auth {
        address base = cauldron.assets(baseId);
        require(base != address(0), "Base not found");

        IJoin baseJoin = ladle.joins(baseId);
        require(address(baseJoin) != address(0), "Join not found");

        IOracle oracle = cauldron.lendingOracles(baseId); // The lending oracles in the Cauldron are also configured to return chi
        require(address(oracle) != address(0), "Chi oracle not found");

        orchestrateFyToken(baseJoin, fyToken);

        // Add fyToken/series to the Cauldron and approve ilks for the series
        cauldron.addSeries(seriesId, baseId, fyToken);
        cauldron.addIlks(seriesId, ilkIds);
        // Register pool in Ladle
        ladle.addPool(seriesId, pool);
    }

    /// @notice A function to create a new FYToken & set the right permissions
    /// @param join Join of the underlying asset
    /// @param fyToken The fyToken
    function orchestrateFyToken(IJoin join, IFYToken fyToken) internal {
        AccessControl fyTokenAC = AccessControl(address(fyToken));

        // Allow the fyToken to pull from the base join for redemption, and to push to mint with underlying
        bytes4[] memory sigs = new bytes4[](2);
        sigs[0] = JOIN;
        sigs[1] = EXIT;
        AccessControl(address(join)).grantRoles(sigs, address(fyToken));

        // Allow the ladle to issue and cancel fyToken
        sigs = new bytes4[](2);
        sigs[0] = MINT;
        sigs[1] = BURN;
        fyTokenAC.grantRoles(sigs, address(ladle));

        // Pass ownership of the fyToken to msg.sender
        fyTokenAC.grantRole(ROOT, msg.sender);
        fyTokenAC.renounceRole(ROOT, address(this));
    }
}
