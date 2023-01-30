// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import { CompositeMultiOracle } from "./CompositeMultiOracle.sol";
import { ICauldron } from "../../interfaces/ICauldron.sol";
import "../../interfaces/DataTypes.sol";

/**
 * @dev A CompositeMultiOracle that can take sources from a Cauldron.
 */
contract CompositeSyncOracle is CompositeMultiOracle {

    event MasterSet(ICauldron indexed master);

    ICauldron public master;

    /// @notice Set the master
    /// @param master_ ICauldron contract used as master
    function setMaster(
        ICauldron master_
    ) external auth {
        master = master_;
        emit MasterSet(master_);
    }

    /// @notice Copy an oracle source from the master. Only works if the source is not set yet.
    /// @param baseId id used for underlying base token
    /// @param quoteId id used for underlying quote token
    function syncSource(
        bytes6 baseId,
        bytes6 quoteId
    )
        external
        returns (IOracle source)
    {
        require(
            sources[baseId][quoteId] == IOracle(address(0)) &&
            sources[quoteId][baseId] == IOracle(address(0)),
            "Only new sources"
        );
        require(master != ICauldron(address(0)), "Master not set");
        DataTypes.SpotOracle memory spotOracle = master.spotOracles(baseId, quoteId);

        source = spotOracle.oracle;
        sources[baseId][quoteId] = source;
        emit SourceSet(baseId, quoteId, source);

        if (baseId != quoteId) {
            sources[quoteId][baseId] = source;
            emit SourceSet(quoteId, baseId, source);
        }
    }
}
