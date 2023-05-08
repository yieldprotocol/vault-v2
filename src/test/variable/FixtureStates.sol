// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "./Fixture.sol";
import {FlashBorrower} from "../../mocks/FlashBorrower.sol";
using Cast for uint256;

abstract contract ZeroState is Fixture {
    // Events we are testing
    event VaultPoured(
        bytes12 indexed vaultId,
        bytes6 indexed baseId,
        bytes6 indexed ilkId,
        int128 ink,
        int128 art
    );
    event VaultStirred(
        bytes12 indexed from,
        bytes12 indexed to,
        uint128 ink,
        uint128 art
    );
    event VaultDestroyed(bytes12 indexed vaultId);
    event VaultTweaked(
        bytes12 indexed vaultId,
        bytes6 indexed baseId,
        bytes6 indexed ilkId
    );
    event VaultGiven(bytes12 indexed vaultId, address indexed receiver);
    event TokenAdded(address indexed token, bool indexed set);
    event IntegrationAdded(address indexed integration, bool indexed set);
    event Approval(address indexed owmer, address indexed spender, uint256 value);
    event SeriesMatured(uint256 chiAtMaturity);
    event Redeemed(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 redeemed
    );
}

abstract contract AssetAddedState is ZeroState {
    function setUp() public virtual override {
        super.setUp();
        addAsset(usdcId, address(usdc), usdcJoin);
        addAsset(daiId, address(dai), daiJoin);
        addAsset(wethId, address(weth), wethJoin);
    }
}

abstract contract IlkAddedState is AssetAddedState {
    function setUp() public virtual override {
        super.setUp();
        ilkIds = new bytes6[](3);
        ilkIds[0] = usdcId;
        ilkIds[1] = daiId;
        ilkIds[2] = wethId;
    }
}

abstract contract CompleteSetup is IlkAddedState {
    function setUp() public virtual override(IlkAddedState) {
        super.setUp();
        cauldron.setSpotOracle(baseId, usdcId, spotOracle, 1000000);
        cauldron.setSpotOracle(baseId, daiId, spotOracle, 1000000);
        cauldron.setSpotOracle(baseId, wethId, spotOracle, 1000000);
        cauldron.addIlks(baseId, ilkIds);
        cauldron.setDebtLimits(
            baseId,
            usdcId,
            uint96(WAD * 20),
            uint24(1e6),
            6
        );
        cauldron.setDebtLimits(
            baseId,
            daiId,
            uint96(WAD * 20),
            uint24(1e3),
            18
        );
        cauldron.setDebtLimits(
            baseId,
            wethId,
            uint96(WAD * 20),
            uint24(1e3),
            18
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
        IERC20(cauldron.assets(ilkId)).approve(
            address(ladle.joins(ilkId)),
            INK
        );
        ladle.pour(vaultId, msg.sender, (INK).i128(), 0);
    }
}

abstract contract BorrowedState is CauldronPouredState {
    function setUp() public virtual override {
        super.setUp();
        ladle.pour(vaultId, address(this), 0, (ART).i128());
    }
}

abstract contract WithTokensAndIntegrationState is CompleteSetup {
    function setUp() public virtual override {
        super.setUp();
        ladle.addToken(address(usdc), true);
        ladle.addIntegration(address(dai), true);
        ladle.addIntegration(user, true);
        ladle.addIntegration(address(restrictedERC20Mock), true);
    }
}

abstract contract ETHVaultBuiltState is CompleteSetup {
    function setUp() public virtual override {
        super.setUp();
        (ethVaultId, ) = ladle.build(baseId, wethId, 9);
    }
}

abstract contract ETHVaultPouredState is ETHVaultBuiltState {
    function setUp() public virtual override {
        super.setUp();
        ladle.wrapEther{value: INK}(address(ladle.joins(wethId)));
        ladle.pour(ethVaultId, address(this), INK.i128(), 0);
    }

    receive() external payable {}
}

abstract contract ETHVaultPouredAndDebtState is ETHVaultPouredState {
    function setUp() public virtual override {
        super.setUp();
        ladle.pour(ethVaultId, address(this), 0, ART.i128());
    }
}

abstract contract VYTokenZeroState is ZeroState {
    address public timelock;
    FlashBorrower public borrower;

    function setUp() public virtual override {
        super.setUp();
        timelock = address(1);
        vyToken.grantRole(VYToken.mint.selector, address(this));
        vyToken.grantRole(VYToken.deposit.selector, address(this));
        vyToken.grantRole(VYToken.setFlashFeeFactor.selector, address(this));

        borrower = new FlashBorrower(vyToken);
        unit = uint128(10 ** ERC20Mock(address(vyToken)).decimals());
        deal(address(vyToken), address(this), unit);
        deal(address(vyToken.underlying()), address(this), unit);
    }
}

abstract contract FlashLoanEnabledState is VYTokenZeroState {
    event Transfer(address indexed src, address indexed dst, uint256 wad);

    function setUp() public override {
        super.setUp();
        vyToken.setFlashFeeFactor(0);
    }
}
