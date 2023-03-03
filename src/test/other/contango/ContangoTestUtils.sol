// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "src/interfaces/DataTypes.sol";
import "src/interfaces/ICauldron.sol";
import "src/interfaces/IJoin.sol";
import "src/interfaces/ILadle.sol";

import "../../utils/Mocks.sol";

library ContangoTestUtils {
    using Mocks for *;

    function mockJoinSetUp(
        ILadle ladle,
        DataTypes.Series memory series,
        DataTypes.Vault memory vault
    ) internal returns (IJoin ilkJoin, IJoin baseJoin) {
        ilkJoin = IJoin(Mocks.mock("IlkJoin"));
        ladle.joins.mock(vault.ilkId, ilkJoin);

        baseJoin = IJoin(Mocks.mock("BaseJoin"));
        ladle.joins.mock(series.baseId, baseJoin);
    }
}
