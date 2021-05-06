// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "@yield-protocol/vault-interfaces/ICauldron.sol";
import "@yield-protocol/vault-interfaces/IFYToken.sol";
import "@yield-protocol/vault-interfaces/DataTypes.sol";
import "@yield-protocol/utils-v2/contracts/access/AccessControl.sol";


interface DssTlmAbstract {
    function ilks(bytes32 ilk) external view returns(address, uint256);
    function sellGem(bytes32 ilk, address usr, uint256 gemAmt) external returns(uint256);
}

interface AuthGemJoinAbstract {
    function gem() external view returns (MaturingGemAbstract);
}

interface MaturingGemAbstract {
}

contract TLMModule {
    event SeriesRegistered(bytes6 indexed seriesId, bytes32 indexed ilk);

    ICauldron public immutable cauldron;
    DssTlmAbstract public immutable tlm;

    mapping (bytes6 => bytes32) public seriesToIlk;

    constructor (ICauldron cauldron_, DssTlmAbstract tlm_) {
        cauldron = cauldron_;
        tlm = tlm_;
    }

    /// @dev Register a series for sale in the TLM.
    function register(bytes6 seriesId, bytes32 ilk)
        external
    {
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
        fyToken.approve(gemJoin, type(uint256).max); // This contract shouldn't hold any fyToken between transactions

        emit SeriesRegistered(seriesId, ilk);
    }

    /// @dev Sell fyDai held in this contract in the TLM.
    function tlmSell(address, bytes memory data)
        external
        returns (uint256)
    {
        (bytes6 seriesId, address to, uint256 fyDaiToSell) = abi.decode(data, (bytes6, address, uint256));
        return tlm.sellGem(seriesToIlk[seriesId], to, fyDaiToSell);
    }
}