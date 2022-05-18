// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import "@yield-protocol/vault-interfaces/src/ICauldronGov.sol";
import "@yield-protocol/vault-interfaces/src/ILadleGov.sol";
import "@yield-protocol/vault-interfaces/src/IJoin.sol";
import "@yield-protocol/vault-interfaces/src/IFYToken.sol";
import "@yield-protocol/yieldspace-v2/contracts/Pool.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20.sol";
import "./FYToken.sol";

/// @dev Ladle orchestrates contract calls throughout the Yield Protocol v2 into useful and efficient governance features.
contract Wandv2 is AccessControl {
    bytes4 public constant JOIN = IJoin.join.selector; // bytes4(keccak256("join(address,uint128)"));
    bytes4 public constant EXIT = IJoin.exit.selector; // bytes4(keccak256("exit(address,uint128)"));
    bytes4 public constant MINT = IFYToken.mint.selector; // bytes4(keccak256("mint(address,uint256)"));
    bytes4 public constant BURN = IFYToken.burn.selector; // bytes4(keccak256("burn(address,uint256)"));

    ICauldronGov public cauldron;
    ILadleGov public ladle;

    constructor(ICauldronGov cauldron_, ILadleGov ladle_) {
        cauldron = cauldron_;
        ladle = ladle_;
    }

    /// @dev Add an existing series to the protocol, by deploying a FYToken, and registering it in the cauldron with the approved ilks
    /// This must be followed by a call to addPool
    function addSeries(
        bytes6 seriesId,
        bytes6 baseId,
        uint32 maturity,
        bytes6[] calldata ilkIds,
        string memory name,
        string memory symbol,
        int128 ts_,
        int128 g1_,
        int128 g2_
    ) external auth {
        address base = cauldron.assets(baseId);
        require(base != address(0), "Base not found");

        IJoin baseJoin = ladle.joins(baseId);
        require(address(baseJoin) != address(0), "Join not found");

        IOracle oracle = cauldron.lendingOracles(baseId); // The lending oracles in the Cauldron are also configured to return chi
        require(address(oracle) != address(0), "Chi oracle not found");

        IFYToken fyToken = setFyToken(baseId, oracle, baseJoin, maturity, name, symbol);
        // Add fyToken/series to the Cauldron and approve ilks for the series
        cauldron.addSeries(seriesId, baseId, fyToken);
        cauldron.addIlks(seriesId, ilkIds);

        setPool(seriesId, fyToken, ts_, g1_, g2_, base);
    }

    function setFyToken(
        bytes6 underlyingId_,
        IOracle oracle,
        IJoin join,
        uint256 maturity,
        string memory name,
        string memory symbol
    ) internal returns (IFYToken) {
        AccessControl fyToken = AccessControl(
            new FYToken(
                underlyingId_,
                oracle,
                join,
                maturity,
                name, // Derive from base and maturity, perhaps
                symbol // Derive from base and maturity, perhaps
            )
        );

        // Allow the fyToken to pull from the base join for redemption, and to push to mint with underlying
        bytes4[] memory sigs = new bytes4[](2);
        sigs[0] = JOIN;
        sigs[1] = EXIT;
        AccessControl(address(join)).grantRoles(sigs, address(fyToken));

        // Allow the ladle to issue and cancel fyToken
        sigs = new bytes4[](2);
        sigs[0] = MINT;
        sigs[1] = BURN;
        fyToken.grantRoles(sigs, address(ladle));

        // Pass ownership of the fyToken to msg.sender
        fyToken.grantRole(ROOT, msg.sender);
        fyToken.renounceRole(ROOT, address(this));

        return IFYToken(address(fyToken));
    }

    function setPool(
        bytes6 seriesId,
        IFYToken fyToken,
        int128 ts_,
        int128 g1_,
        int128 g2_,
        address base
    ) internal {
        // Create the pool for the base and fyToken
        Pool pool = new Pool(IERC20(base), fyToken, ts_, g1_, g2_);

        // Register pool in Ladle
        ladle.addPool(seriesId, address(pool));
    }
}
