// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./Fixture.sol";
using CastU256I128 for uint256;
abstract contract ZeroState is Fixture {
    event VaultPoured(bytes12 indexed vaultId, bytes6 indexed baseId, bytes6 indexed ilkId, int128 ink, int128 art);
    event VaultStirred(bytes12 indexed from, bytes12 indexed to, uint128 ink, uint128 art);
}

abstract contract AssetAddedState is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        addAsset(usdcId, address(usdc), usdcJoin);
        addAsset(daiId, address(dai), daiJoin);
    }
}

abstract contract IlkAddedState is AssetAddedState {
    function setUp() public virtual override {
        super.setUp();
        cauldron.setRateOracle(usdcId, IOracle(address(chiRateOracle)));

        ilkIds = new bytes6[](2);
        ilkIds[0] = usdcId;
        ilkIds[1] = daiId;
    }
}

abstract contract RateOracleAddedState is AssetAddedState {
    function setUp() public virtual override {
        super.setUp();
        cauldron.setRateOracle(usdcId, IOracle(address(chiRateOracle)));
    }
}

abstract contract CompleteSetup is IlkAddedState, RateOracleAddedState {
    function setUp()
        public
        virtual
        override(IlkAddedState, RateOracleAddedState)
    {
        super.setUp();
        cauldron.setSpotOracle(baseId, usdcId, spotOracle, 1000000);
        cauldron.setSpotOracle(baseId, daiId, spotOracle, 1000000);
        cauldron.addIlks(baseId, ilkIds);
        cauldron.setDebtLimits(
            baseId,
            usdcId,
            uint96(WAD * 20),
            uint24(1e6),
            6
        );
    }
}

abstract contract VaultBuiltState is CompleteSetup {
    function setUp() public virtual override {
        super.setUp();
        cauldron.build(address(this), vaultId, baseId, usdcId);
    }
}

abstract contract CauldronPouredState is VaultBuiltState {
    function setUp() public virtual override {
        super.setUp();
        (address owner, , bytes6 ilkId) = cauldron.vaults(vaultId);
        deal(cauldron.assets(ilkId), owner, INK);
        IERC20(cauldron.assets(ilkId)).approve(address(ladle.joins(ilkId)), INK);
        ladle.pour(vaultId,msg.sender,(INK).i128(),0);
    }
}

 abstract contract BorrowedState is CauldronPouredState {
    function setUp() public override {
        super.setUp();
        ladle.pour(vaultId, address(this), 0, (ART).i128());
    }
 }
