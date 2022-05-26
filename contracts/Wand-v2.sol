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
contract Wandv2 is AccessControl {
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
    /// @param maturity Maturity date for the fyToken
    /// @param ilkIds The ilk for the fyToken
    /// @param name Name of the fyToken
    /// @param symbol Symbol of the fyToken
    /// @param ts time stretch, in 64.64
    /// @param g1 in 64.64
    /// @param g2 in 64.64
    function addSeries(
        bytes6 seriesId,
        bytes6 baseId,
        uint32 maturity,
        bytes6[] calldata ilkIds,
        string memory name,
        string memory symbol,
        int128 ts,
        int128 g1,
        int128 g2
    ) external auth {
        address base = cauldron.assets(baseId);
        require(base != address(0), "Base not found");

        IJoin baseJoin = ladle.joins(baseId);
        require(address(baseJoin) != address(0), "Join not found");

        IOracle oracle = cauldron.lendingOracles(baseId); // The lending oracles in the Cauldron are also configured to return chi
        require(address(oracle) != address(0), "Chi oracle not found");

        IFYToken fyToken = createFyToken(baseId, oracle, baseJoin, maturity, name, symbol);
        createPool(seriesId, fyToken, ts, g1, g2, base);

        // Add fyToken/series to the Cauldron and approve ilks for the series
        cauldron.addSeries(seriesId, baseId, fyToken);
        cauldron.addIlks(seriesId, ilkIds);
    }

    /// @notice A function to create a new FYToken & set the right permissions
    /// @param underlyingId_ id of the underlying asset
    /// @param oracle Lending oracle
    /// @param join Join of the underlying asset
    /// @param maturity Maturity date for the fyToken
    /// @param name Name of the fyToken
    /// @param symbol Symbol of the fyToken
    /// @return IFYToken The fyToken that was created
    function createFyToken(
        bytes6 underlyingId_,
        IOracle oracle,
        IJoin join,
        uint256 maturity,
        string memory name,
        string memory symbol
    ) internal returns (IFYToken) {
        IFYToken fyToken = IFYToken(
            new FYToken(
                underlyingId_,
                oracle,
                join,
                maturity,
                name,
                symbol
            )
        );
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

        return fyToken;
    }

    /// @notice Creates a pool with the given parameters
    /// @param seriesId The id for the series
    /// @param fyToken The fyToken for the series
    /// @param ts time stretch, in 64.64
    /// @param g1 in 64.64
    /// @param g2 in 64.64
    /// @param base address of the base asset
    function createPool(
        bytes6 seriesId,
        IFYToken fyToken,
        int128 ts,
        int128 g1,
        int128 g2,
        address base
    ) internal {
        // Create the pool for the base and fyToken
        Pool pool = new Pool(IERC20(base), fyToken, ts, g1, g2);
        // Register pool in Ladle
        ladle.addPool(seriesId, address(pool));
    }
}
