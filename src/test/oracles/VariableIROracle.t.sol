// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import "../../oracles/VariableInterestRateOracle.sol";
import "../utils/TestConstants.sol";
import "../utils/Mocks.sol";

abstract contract ZeroState is Test, TestConstants {
    using Mocks for *;

    VariableInterestRateOracle public variableInterestRateOracle;

    struct InterestRateParameter {
        /// @dev rate accumulated so far - check `get` for details
        uint256 accumulated;
        /// @dev time when `accumulated` was last updated
        uint256 lastUpdated;
        // @dev optimalUsageRate
        uint256 optimalUsageRate;
        // @dev baseVariableBorrowRate
        uint256 baseVariableBorrowRate;
        // @dev slope1
        uint256 slope1;
        // @dev slope2
        uint256 slope2;
        // @dev join
        IJoin join;
        // @dev ilks
        bytes6[] ilks;
    }

    address timelock;
    address underlying;
    bytes6 public baseOne = 0x6d1caec02cbf;
    bytes6 public baseTwo = 0x8a4fee8b848e;
    ICauldron internal cauldron;
    IJoin ethJoin;
    IJoin daiJoin;
    IJoin usdcJoin;
    // IJoin fraxJoin = IJoin();
    // IJoin usdtJoin = IJoin();

    modifier onlyMock() {
        if (!vm.envOr(MOCK, true)) return;
        _;
    }

    InterestRateParameter internal ethParameters =
        InterestRateParameter({
            optimalUsageRate: 450000,
            accumulated: 1000000000000000000,
            lastUpdated: block.timestamp,
            baseVariableBorrowRate: 0,
            slope1: 40000,
            slope2: 3000000,
            join: ethJoin,
            ilks: new bytes6[](2)
        });
    InterestRateParameter internal daiParameters =
        InterestRateParameter({
            optimalUsageRate: 900000,
            accumulated: 1000000000000000000,
            lastUpdated: block.timestamp,
            baseVariableBorrowRate: 0,
            slope1: 40000,
            slope2: 600000,
            join: daiJoin,
            ilks: new bytes6[](2)
        });
    InterestRateParameter internal usdcParameters =
        InterestRateParameter({
            optimalUsageRate: 450000,
            accumulated: 1000000,
            lastUpdated: block.timestamp,
            baseVariableBorrowRate: 0,
            slope1: 40000,
            slope2: 600000,
            join: usdcJoin,
            ilks: new bytes6[](2)
        });

    InterestRateParameter internal sourceParameters;

    function setUpMock() public {
        usdcJoin = IJoin(Mocks.mock("Join"));
        daiJoin = IJoin(Mocks.mock("Join"));
        ethJoin = IJoin(Mocks.mock("Join"));
        cauldron = ICauldron(Mocks.mock("Cauldron"));
        variableInterestRateOracle = new VariableInterestRateOracle(cauldron);
        
        variableInterestRateOracle.grantRole(variableInterestRateOracle.setSource.selector, address(this));
        variableInterestRateOracle.grantRole(
            variableInterestRateOracle.updateParameters.selector,
            address(this)
        );
        sourceParameters.join = usdcJoin;

        baseOne = 0x6d1caec02cbf;
        baseTwo = 0x8a4fee8b848e;

        DataTypes.Debt memory debt = DataTypes.Debt({
            max: 0,
            min: 0,
            dec: 0,
            sum: 10000e18 // Used by oracle
        });
        cauldron.debt.mock(baseOne, baseOne, debt);
        for (uint256 i = 0; i < sourceParameters.ilks.length; i++) {
            cauldron.debt.mock(baseOne, sourceParameters.ilks[i], debt);
        }

        sourceParameters.join.storedBalance.mock(100000e18);
    }

    function setUpHarness(string memory network) public {
        vm.createSelectFork(MAINNET, 16877055);
        ethJoin = IJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0);
        daiJoin = IJoin(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc);
        usdcJoin = IJoin(0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4);
        timelock = addresses[network][TIMELOCK];

        variableInterestRateOracle = new VariableInterestRateOracle(
            ICauldron(addresses[network][CAULDRON])
        );
        sourceParameters.join = daiJoin;
        baseOne = bytes6(0x303100000000);
        underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        variableInterestRateOracle.grantRole(variableInterestRateOracle.setSource.selector, address(this));
        variableInterestRateOracle.grantRole(
            variableInterestRateOracle.updateParameters.selector,
            address(this)
        );
    }

    function setUp() public virtual {
        sourceParameters = daiParameters;
        sourceParameters.ilks[0] = USDC;
        sourceParameters.ilks[1] = ETH;
        // string memory rpc = vm.envOr(RPC, MAINNET);
        // vm.createSelectFork(rpc);
        // string memory network = vm.envOr(NETWORK, LOCALHOST);
        // setUpMock();
        // if (vm.envOr(MOCK, true))
        setUpMock();
        // else
        // setUpHarness("MAINNET");
    }
}

abstract contract WithSourceSet is ZeroState {
    function setUp() public override {
        super.setUp();
        variableInterestRateOracle.setSource(
            baseOne,
            RATE,
            sourceParameters.optimalUsageRate,
            sourceParameters.accumulated,
            sourceParameters.baseVariableBorrowRate,
            sourceParameters.slope1,
            sourceParameters.slope2,
            sourceParameters.join,
            sourceParameters.ilks
        );
    }
}

contract VariableInterestRateOracleOracleTest is ZeroState {
    function testSetSourceOnlyOnce() public {
        variableInterestRateOracle.setSource(
            baseOne,
            RATE,
            sourceParameters.optimalUsageRate,
            sourceParameters.accumulated,
            sourceParameters.baseVariableBorrowRate,
            sourceParameters.slope1,
            sourceParameters.slope2,
            sourceParameters.join,
            sourceParameters.ilks
        );
        vm.expectRevert("Source is already set");
        variableInterestRateOracle.setSource(
            baseOne,
            RATE,
            sourceParameters.optimalUsageRate,
            sourceParameters.accumulated,
            sourceParameters.baseVariableBorrowRate,
            sourceParameters.slope1,
            sourceParameters.slope2,
            sourceParameters.join,
            sourceParameters.ilks
        );
    }

    function testCannotCallUninitializedSource() public {
        vm.expectRevert("Source not found");
        variableInterestRateOracle.updateParameters(
            baseOne,
            RATE,
            sourceParameters.optimalUsageRate,
            sourceParameters.baseVariableBorrowRate,
            sourceParameters.slope1,
            sourceParameters.slope2,
            sourceParameters.join
        );
    }

    function testCannotCallStaleInterestRateParameter() public {
        variableInterestRateOracle.setSource(
            baseOne,
            RATE,
            sourceParameters.optimalUsageRate,
            sourceParameters.accumulated,
            sourceParameters.baseVariableBorrowRate,
            sourceParameters.slope1,
            sourceParameters.slope2,
            sourceParameters.join,
            sourceParameters.ilks
        );
        skip(100);
        vm.expectRevert("stale InterestRateParameter");
        variableInterestRateOracle.updateParameters(
            baseOne,
            RATE,
            sourceParameters.optimalUsageRate,
            sourceParameters.baseVariableBorrowRate,
            sourceParameters.slope1,
            sourceParameters.slope2,
            sourceParameters.join
        );
    }

    function testRevertOnSourceUnknown() public {
        variableInterestRateOracle.setSource(
            baseOne,
            RATE,
            sourceParameters.optimalUsageRate,
            sourceParameters.accumulated,
            sourceParameters.baseVariableBorrowRate,
            sourceParameters.slope1,
            sourceParameters.slope2,
            sourceParameters.join,
            sourceParameters.ilks
        );
        vm.expectRevert("Source not found");
        variableInterestRateOracle.peek(bytes32(baseTwo), RATE, WAD);
        vm.expectRevert("Source not found");
        variableInterestRateOracle.peek(bytes32(baseOne), CHI, WAD);
    }

    // function testDoesNotMixUpSources() public {
    //     variableInterestRateOracle.setSource(
    //         baseOne,
    //         RATE,
    //         sourceParameters.optimalUsageRate,
    //         sourceParameters.baseVariableBorrowRate,
    //         sourceParameters.slope1,
    //         sourceParameters.slope2,
    //         sourceParameters.join
    //     );
    //     variableInterestRateOracle.setSource(baseOne, CHI, WAD * 2, WAD);
    //     variableInterestRateOracle.setSource(baseTwo, RATE, WAD * 3, WAD);
    //     variableInterestRateOracle.setSource(baseTwo, CHI, WAD * 4, WAD);

    //     uint256 amount;
    //     (amount, ) = variableInterestRateOracle.peek(bytes32(baseOne), RATE, WAD);
    //     assertEq(amount, WAD, "Conversion unsuccessful");
    //     (amount, ) = variableInterestRateOracle.peek(bytes32(baseOne), CHI, WAD);
    //     assertEq(amount, WAD * 2, "Conversion unsuccessful");
    //     (amount, ) = variableInterestRateOracle.peek(bytes32(baseTwo), RATE, WAD);
    //     assertEq(amount, WAD * 3, "Conversion unsuccessful");
    //     (amount, ) = variableInterestRateOracle.peek(bytes32(baseTwo), CHI, WAD);
    //     assertEq(amount, WAD * 4, "Conversion unsuccessful");
    // }
}

contract WithSourceSetTest is WithSourceSet {
    function testComputesWithoutCheckpoints() public {
        uint256 amount;
        (amount, ) = variableInterestRateOracle.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        skip(10);
        (amount, ) = variableInterestRateOracle.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        skip(2);
        (amount, ) = variableInterestRateOracle.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
    }

    function testComputesWithCheckpointing() public {
        uint256 amount;
        vm.roll(block.number + 1);
        skip(1);
        (amount, ) = variableInterestRateOracle.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        vm.roll(block.number + 1);
        skip(10);
        (amount, ) = variableInterestRateOracle.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
    }

    function testUpdatesPeek() public {
        uint256 amount;
        skip(10);
        (amount, ) = variableInterestRateOracle.peek(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        vm.roll(block.number + 1);
        variableInterestRateOracle.get(bytes32(baseOne), RATE, WAD);
        (amount, ) = variableInterestRateOracle.peek(bytes32(baseOne), RATE, WAD);
    }
}
