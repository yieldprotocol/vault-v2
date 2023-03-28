// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "forge-std/src/Vm.sol";
import {TestConstants} from "../utils/TestConstants.sol";
import {TestExtensions} from "../utils/TestExtensions.sol";
import "../../variable/VRLadle.sol";
import "../../variable/VRRouter.sol";
import "../../variable/VRCauldron.sol";
import "../../variable/VYToken.sol";
import "../../variable/VRWitch.sol";
import "../../oracles/compound/CompoundMultiOracle.sol";
import "../../oracles/chainlink/ChainlinkMultiOracle.sol";
import "../../oracles/accumulator/AccumulatorMultiOracle.sol";
import "../../mocks/oracles/compound/CTokenRateMock.sol";
import "../../mocks/oracles/compound/CTokenChiMock.sol";
import "../../mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol";
import "../../FlashJoin.sol";
import "../../interfaces/ILadle.sol";
import "../../interfaces/IRouter.sol";
import "../../interfaces/ICauldron.sol";
import "../../interfaces/IJoin.sol";
import "../../interfaces/DataTypes.sol";
import "../../variable/interfaces/IVRCauldron.sol";
import "../../mocks/USDCMock.sol";
import "../../mocks/WETH9Mock.sol";
import "../../mocks/DAIMock.sol";
import "../../mocks/ERC20Mock.sol";
import "../../mocks/RestrictedERC20Mock.sol";
import "@yield-protocol/utils-v2/src/interfaces/IWETH9.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import "@yield-protocol/utils-v2/src/utils/Cast.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";
import "openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

using Cast for uint256;
using Cast for uint256;
using Math for uint256;

abstract contract Fixture is Test, TestConstants, TestExtensions {
    address public admin = makeAddr("admin");
    address public user = makeAddr("user");
    VRCauldron public cauldron;
    VRRouter public router;
    VRLadle public ladle;
    VRWitch public witch;
    USDCMock public usdc;
    WETH9Mock public weth;
    DAIMock public dai;
    ERC20Mock public base;
    ERC20Mock public otherERC20;
    FlashJoin public usdcJoin;
    FlashJoin public wethJoin;
    FlashJoin public daiJoin;
    FlashJoin public baseJoin;
    bytes6 public usdcId = USDC;
    bytes6 public wethId = ETH;
    bytes6 public daiId = DAI;
    bytes6 public otherIlkId = bytes6("OTHER");
    bytes6 public baseId = bytes6("BASE");
    VYToken public vyToken;
    VYToken public wethVYToken;
    VYToken public daiVYToken;
    CTokenRateMock public cTokenRateMock;
    CTokenChiMock public cTokenChiMock;
    RestrictedERC20Mock public restrictedERC20Mock;
    AccumulatorMultiOracle public chiRateOracle;
    ChainlinkMultiOracle public spotOracle;
    ChainlinkAggregatorV3Mock public ethAggregator;
    ChainlinkAggregatorV3Mock public daiAggregator;
    ChainlinkAggregatorV3Mock public usdcAggregator;
    ChainlinkAggregatorV3Mock public baseAggregator;

    ERC1967Proxy public cauldronProxy;
    ERC1967Proxy public ladleProxy;
    ERC1967Proxy public vyTokenProxy;

    bytes12 public vaultId = 0x000000000000000000000001;
    bytes12 public zeroVaultId = 0x000000000000000000000000;
    bytes12 public otherVaultId = 0x000000000000000000000002;
    bytes12 public ethVaultId;

    bytes6 public zeroId = 0x000000000000;
    bytes6[] public ilkIds;

    uint256 public INK = WAD * 100000;
    uint256 public ART = WAD;
    uint256 public FEE = 1000;
    uint128 public unit;

    function setUp() public virtual {
        // Deploying mock tokens
        usdc = new USDCMock();
        weth = new WETH9Mock();
        dai = new DAIMock();
        base = new ERC20Mock("Base", "BASE");
        otherERC20 = new ERC20Mock("Other ERC20", "OTHERERC20");
        restrictedERC20Mock = new RestrictedERC20Mock(
            "Restricted",
            "RESTRICTED"
        );

        // Deploying mock oracles
        ethAggregator = new ChainlinkAggregatorV3Mock();
        daiAggregator = new ChainlinkAggregatorV3Mock();
        usdcAggregator = new ChainlinkAggregatorV3Mock();
        baseAggregator = new ChainlinkAggregatorV3Mock();

        // Deploying core contracts
        cauldron = new VRCauldron();
        cauldronProxy = new ERC1967Proxy(
            address(cauldron),
            abi.encodeWithSignature("initialize(address)", address(this))
        );
        cauldron = VRCauldron(address(cauldronProxy));
        router = new VRRouter();
        ladle = new VRLadle(
            IVRCauldron(address(cauldron)),
            IRouter(address(router)),
            IWETH9(address(weth))
        );

        chiRateOracle = new AccumulatorMultiOracle();
        spotOracle = new ChainlinkMultiOracle();

        ladleProxy = new ERC1967Proxy(
            address(ladle),
            abi.encodeWithSignature("initialize(address)", address(this))
        );
        ladle = VRLadle(payable(ladleProxy));
        router.initialize(address(ladle));

        witch = new VRWitch(
            ICauldron(address(cauldron)),
            ILadle(address(ladle))
        );
        ERC1967Proxy witchProxy = new ERC1967Proxy(
            address(witch),
            abi.encodeWithSignature(
                "initialize(address,address)",
                ILadle(address(ladle)),
                address(this)
            )
        );
        witch = VRWitch(address(witchProxy));

        // Setting permissions
        ladleGovAuth();
        cauldronGovAuth(address(ladle));
        cauldronGovAuth(address(this));

        restrictedERC20Mock = new RestrictedERC20Mock(
            "Restricted",
            "RESTRICTED"
        );

        usdcJoin = new FlashJoin(address(usdc));
        wethJoin = new FlashJoin(address(weth));
        daiJoin = new FlashJoin(address(dai));
        baseJoin = new FlashJoin(address(base));

        vyToken = new VYToken(
            baseId,
            IOracle(address(chiRateOracle)),
            IJoin(baseJoin),
            base.name(),
            base.symbol()
        );
        /// Orchestrating the protocol
        setUpOracles();

        vyToken = new VYToken(
            baseId,
            IOracle(address(chiRateOracle)),
            IJoin(baseJoin),
            base.name(),
            base.symbol()
        );

        vyTokenProxy = new ERC1967Proxy(
            address(vyToken),
            abi.encodeWithSignature("initialize(address)", address(this))
        );

        vyToken = VYToken(address(vyTokenProxy));

        // Adding assets & making base
        addAsset(baseId, address(base), baseJoin);
        makeBase(baseId, address(base), baseJoin, address(chiRateOracle), 9);

        // Setting permission for vyToken
        bytes4[] memory roles = new bytes4[](2);
        roles[0] = Join.join.selector;
        roles[1] = Join.exit.selector;
        baseJoin.grantRoles(roles, address(vyToken));
    }

    function setUpOracles() internal {
        // Granting permissions
        chiRateOracle.grantRole(
            AccumulatorMultiOracle.setSource.selector,
            address(this)
        );
        chiRateOracle.grantRole(
            AccumulatorMultiOracle.updatePerSecondRate.selector,
            address(this)
        );
        spotOracle.grantRole(
            ChainlinkMultiOracle.setSource.selector,
            address(this)
        );
        // Setting up the rate oracle
        chiRateOracle.setSource(baseId, RATE, WAD, WAD * 2); // Borrowing rate
        chiRateOracle.setSource(baseId, CHI, WAD, WAD * 2); // Lending rate
        // Setting up the chainlink mock oracle prices
        ethAggregator.set(1e18 / 2);
        daiAggregator.set(1e18 / 2);
        usdcAggregator.set(1e18 / 2);
        baseAggregator.set(1e18 / 2);

        // Setting up the spot oracle
        spotOracle.setSource(
            ETH,
            IERC20Metadata(address(weth)),
            usdcId,
            IERC20Metadata(address(usdc)),
            address(usdcAggregator)
        );
        spotOracle.setSource(
            ETH,
            IERC20Metadata(address(weth)),
            baseId,
            IERC20Metadata(address(base)),
            address(ethAggregator)
        );
        spotOracle.setSource(
            ETH,
            IERC20Metadata(address(weth)),
            daiId,
            IERC20Metadata(address(dai)),
            address(daiAggregator)
        );
    }

    // ----------------- Permissions ----------------- //

    function ladleGovAuth() public {
        bytes4[] memory roles = new bytes4[](5);
        roles[0] = VRLadle.addJoin.selector;
        roles[2] = VRLadle.setFee.selector;
        roles[3] = VRLadle.addToken.selector;
        roles[4] = VRLadle.addIntegration.selector;
        ladle.grantRoles(roles, address(this));
    }

    function cauldronGovAuth(address govAuth) public {
        bytes4[] memory roles = new bytes4[](13);
        roles[0] = VRCauldron.addAsset.selector;
        roles[1] = VRCauldron.addIlks.selector;
        roles[2] = VRCauldron.setDebtLimits.selector;
        roles[3] = VRCauldron.setRateOracle.selector;
        roles[4] = VRCauldron.setSpotOracle.selector;
        roles[5] = VRCauldron.addBase.selector;
        roles[6] = VRCauldron.destroy.selector;
        roles[7] = VRCauldron.build.selector;
        roles[8] = VRCauldron.pour.selector;
        roles[9] = VRCauldron.give.selector;
        roles[10] = VRCauldron.tweak.selector;
        roles[11] = VRCauldron.stir.selector;
        roles[12] = VRCauldron.slurp.selector;
        cauldron.grantRoles(roles, govAuth);
    }

    // ----------------- Helpers ----------------- //
    function addAsset(
        bytes6 assetId,
        address assetAddress,
        FlashJoin join
    ) public {
        cauldron.addAsset(assetId, assetAddress);
        ladle.addJoin(assetId, join);

        bytes4[] memory roles = new bytes4[](2);
        roles[0] = Join.join.selector;
        roles[1] = Join.exit.selector;
        join.grantRoles(roles, address(ladle));
    }

    function makeBase(
        bytes6 assetId,
        address assetAddress,
        FlashJoin join,
        address chirateoracle,
        uint8 salt
    ) internal {
        cauldron.setRateOracle(assetId, IOracle(chirateoracle));
        cauldron.addBase(assetId);

        cauldron.setSpotOracle(
            assetId,
            assetId,
            IOracle(chirateoracle),
            1000000
        );
        bytes6[] memory ilk = new bytes6[](1);
        ilk[0] = assetId;
        cauldron.addIlks(assetId, ilk);
        cauldron.setDebtLimits(
            assetId,
            assetId,
            uint96(WAD * 20),
            uint24(1e6),
            18
        );
        (bytes12 vaultId_, ) = ladle.build(assetId, assetId, salt);
        // cauldron.build(address(this), vaultId_, assetId, assetId);
        IERC20(assetAddress).approve(address(join), INK * 10);
        deal(assetAddress, address(this), INK * 10);
        ladle.pour(vaultId_, address(this), (INK * 10).i128(), 0);
    }

    function getAbove(
        int128 ink,
        int128 art,
        bytes12 vault
    ) internal returns (bool) {
        (, bytes6 baseId, bytes6 ilkId) = cauldron.vaults(vault);

        (IOracle oracle, uint32 ratio1) = cauldron.spotOracles(baseId, ilkId);
        uint256 ratio = uint256(ratio1) * 1e12; // Normalized to 18 decimals
        (uint256 inkValue, ) = oracle.get(ilkId, baseId, uint256(int(ink))); // ink * spot
        uint256 baseValue = cauldron.debtToBase(baseId, uint128(art));
        return inkValue.i256() - baseValue.wmul(ratio).i256() >= 0;
    }

    function giveMeDustAndLine(
        bytes12 vault
    ) internal view returns (uint128 dust, uint128 line) {
        (, bytes6 baseId, bytes6 ilkId) = cauldron.vaults(vault);
        (uint96 max, uint24 min, uint8 dec, ) = cauldron.debt(baseId, ilkId);
        dust = min * uint128(10) ** dec;
        line = max * uint128(10) ** dec;
    }
}
