// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "forge-std/src/console.sol";
import "forge-std/src/Vm.sol";
import {TestConstants} from "../utils/TestConstants.sol";
import {TestExtensions} from "../utils/TestExtensions.sol";
import "../../variable/VRLadle.sol";
import "../../variable/VRCauldron.sol";
import "../../variable/VYToken.sol";
import "../../Witch.sol";
import "../../oracles/compound/CompoundMultiOracle.sol";
import "../../oracles/chainlink/ChainlinkMultiOracle.sol";
import "../../mocks/oracles/compound/CTokenRateMock.sol";
import "../../mocks/oracles/compound/CTokenChiMock.sol";
import "../../mocks/oracles/chainlink/ChainlinkAggregatorV3Mock.sol";
import "../../FlashJoin.sol";
import "../../interfaces/ILadle.sol";
import "../../interfaces/ICauldron.sol";
import "../../interfaces/IJoin.sol";
import "../../interfaces/DataTypes.sol";
import "../../variable/interfaces/IVRCauldron.sol";
import "../../mocks/USDCMock.sol";
import "../../mocks/WETH9Mock.sol";
import "../../mocks/DAIMock.sol";
import "../../mocks/ERC20Mock.sol";
import "@yield-protocol/utils-v2/contracts/interfaces/IWETH9.sol";
import "@yield-protocol/utils-v2/contracts/token/IERC20Metadata.sol";

abstract contract Fixture is Test, TestConstants, TestExtensions {
    address public admin = makeAddr("admin");
    address public user = makeAddr("user");
    VRCauldron public cauldron;
    VRLadle public ladle;
    Witch public witch;
    USDCMock public usdc;
    WETH9Mock public weth;
    DAIMock public dai;
    ERC20Mock public base;
    FlashJoin public usdcJoin;
    FlashJoin public wethJoin;
    FlashJoin public daiJoin;
    bytes6 public usdcId = bytes6("USDC");
    bytes6 public wethId = bytes6("WETH");
    bytes6 public daiId = bytes6("DAI");
    bytes6 public otherIlkId = bytes6("OTHER");
    bytes6 public baseId = bytes6("BASE");
    VYToken public usdcYToken;
    VYToken public wethYToken;
    VYToken public daiYToken;
    CTokenRateMock public cTokenRateMock;
    CTokenChiMock public cTokenChiMock;
    CompoundMultiOracle public chiRateOracle;
    ChainlinkMultiOracle public spotOracle;
    ChainlinkAggregatorV3Mock public ethAggregator;
    ChainlinkAggregatorV3Mock public daiAggregator;
    ChainlinkAggregatorV3Mock public usdcAggregator;

    bytes12 public vaultId = 0x000000000000000000000001;
    bytes12 public zeroVaultId = 0x000000000000000000000000;

    bytes6 public zeroId = 0x000000000000;

    bytes6[] public ilkIds;

    function setUp() public virtual {
        cauldron = new VRCauldron();
        ladle = new VRLadle(
            IVRCauldron(address(cauldron)),
            IWETH9(address(weth))
        );
        witch = new Witch(ICauldron(address(cauldron)), ILadle(address(ladle)));

        usdc = new USDCMock();
        weth = new WETH9Mock();
        dai = new DAIMock();
        base = new ERC20Mock("Base", "BASE");

        usdcJoin = new FlashJoin(address(usdc));
        wethJoin = new FlashJoin(address(weth));
        daiJoin = new FlashJoin(address(dai));

        ladleGovAuth();
        cauldronGovAuth();
        setUpOracles();
        makeBase();
    }

    function setUpOracles() internal {
        chiRateOracle = new CompoundMultiOracle();

        cTokenRateMock = new CTokenRateMock();
        cTokenRateMock.set(1e18 * 2 * 10000000000);

        cTokenChiMock = new CTokenChiMock();
        cTokenChiMock.set(1e18 * 10000000000);

        chiRateOracle.grantRole(
            CompoundMultiOracle.setSource.selector,
            address(this)
        );
        chiRateOracle.setSource(baseId, RATE, address(cTokenRateMock));
        chiRateOracle.setSource(baseId, CHI, address(cTokenChiMock));

        ethAggregator = new ChainlinkAggregatorV3Mock();
        ethAggregator.set(1e18 / 2);

        daiAggregator = new ChainlinkAggregatorV3Mock();
        daiAggregator.set(1e18 / 2);

        usdcAggregator = new ChainlinkAggregatorV3Mock();
        usdcAggregator.set(1e18 / 2);

        spotOracle = new ChainlinkMultiOracle();
        spotOracle.grantRole(
            ChainlinkMultiOracle.setSource.selector,
            address(this)
        );

        spotOracle.setSource(
            baseId,
            IERC20Metadata(address(base)),
            usdcId,
            IERC20Metadata(address(usdc)),
            address(usdcAggregator)
        );
        spotOracle.setSource(
            baseId,
            IERC20Metadata(address(base)),
            wethId,
            IERC20Metadata(address(weth)),
            address(ethAggregator)
        );
        spotOracle.setSource(
            baseId,
            IERC20Metadata(address(base)),
            daiId,
            IERC20Metadata(address(dai)),
            address(daiAggregator)
        );
    }

    function makeBase() internal {
        cauldron.addAsset(baseId, address(base));
        cauldron.setRateOracle(baseId, IOracle(address(chiRateOracle)));
        cauldron.addBase(baseId);
    }

    function ladleGovAuth() public {
        bytes4[] memory roles = new bytes4[](3);
        roles[0] = VRLadle.addJoin.selector;
        roles[1] = VRLadle.addModule.selector;
        roles[2] = VRLadle.setFee.selector;
        ladle.grantRoles(roles, address(this));
    }

    function cauldronGovAuth() public {
        bytes4[] memory roles = new bytes4[](8);
        roles[0] = VRCauldron.addAsset.selector;
        roles[1] = VRCauldron.addIlks.selector;
        roles[2] = VRCauldron.setDebtLimits.selector;
        roles[3] = VRCauldron.setRateOracle.selector;
        roles[4] = VRCauldron.setSpotOracle.selector;
        roles[5] = VRCauldron.addBase.selector;
        roles[6] = VRCauldron.destroy.selector;
        roles[7] = VRCauldron.build.selector;
        cauldron.grantRoles(roles, address(this));
    }
}
