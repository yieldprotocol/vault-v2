// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.6;
import "@yield-protocol/vault-interfaces/ICauldron.sol";
import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "@yield-protocol/vault-interfaces/DataTypes.sol";
import "../LadleStorage.sol";


interface DssTlmAbstract {
    function ilks(bytes32 ilk) external view returns(address, uint256);
    function sellGem(bytes32 ilk, address usr, uint256 gemAmt) external returns(uint256);
}

interface AuthGemJoinAbstract {
    function gem() external view returns (MaturingGemAbstract);
}

interface MaturingGemAbstract {
}

/// @dev 
contract TLMModule is LadleStorage {
    event SeriesRegistered(bytes6 indexed seriesId, bytes32 indexed ilk);

    // The TLMModule inherits the same storage layout as the Ladle.
    // When the Ladle delegatecalls into the TLMModule, the functions called have access to the Ladle storage.
    // The following two variables are avaiable to delegatecalls, being immutable
    DssTlmAbstract public immutable tlm;
    TLMModule public immutable tlmModule;

    // The TLMModule is also deployed, and called normally to register the series to ilk correspondence
    // The following is not directly available through delegatecall, but can be found at `tlm.seriesToIlk`
    mapping (bytes6 => bytes32) public seriesToIlk;

    constructor (ICauldron cauldron_, IWETH9 weth_, DssTlmAbstract tlm_) 
        LadleStorage(cauldron_, weth_) {
        tlm = tlm_;
        tlmModule = this;
    }

    /// @dev Register a series for sale in the TLM. Can't be called via `delegatecall`.
    /// Must be followed by a call to `approve`.
    function register(bytes6 seriesId, bytes32 ilk)
        external
    {
        require(address(this) == address(tlmModule), "No delegatecall");
        DataTypes.Series memory series = cauldron.series(seriesId);
        IFYToken fyToken = series.fyToken;
        require (fyToken != IFYToken(address(0)), "Series not found");
        
        // Check the maturity and ilk match
        (address gemJoin,) = tlm.ilks(ilk);
        require (gemJoin != address(0), "Ilk not found");

        require(
            address(AuthGemJoinAbstract(gemJoin).gem()) == address(fyToken),
            "Mismatched FYDai and Gem"
        );

        // Register the correspondence
        seriesToIlk[seriesId] = ilk;

        emit SeriesRegistered(seriesId, ilk);
    }

    /// @dev Approve a fyToken to be taken by the TLM. Can be used via delegatecall.
    function approve(bytes6 seriesId)
        external
    {
        DataTypes.Series memory series = cauldron.series(seriesId);
        IFYToken fyToken = series.fyToken;
        require (fyToken != IFYToken(address(0)), "Series not found");

        bytes32 ilk = tlmModule.seriesToIlk(seriesId);
        require (ilk != bytes32(0), "Series not registered");
        
        (address gemJoin,) = tlm.ilks(ilk);
        require (gemJoin != address(0), "Ilk not found");

        fyToken.approve(gemJoin, type(uint256).max); // This contract shouldn't hold any fyToken between transactions
    }

    /// @dev Sell fyDai held in this contract in the TLM. Can be used via delegatecall.
    function sell(bytes6 seriesId, address to, uint256 fyDaiToSell)
        external
        returns (uint256)
    {
        return tlm.sellGem(tlmModule.seriesToIlk(seriesId), to, fyDaiToSell);
    }
}