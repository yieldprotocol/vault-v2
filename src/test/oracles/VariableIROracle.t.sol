// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import "../../oracles/VariableInterestRateOracle.sol";
import "../utils/TestConstants.sol";
import "../utils/Mocks.sol";

abstract contract ZeroState is Test, TestConstants {
    VariableInterestRateOracle public accumulator;

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
    }

    address timelock;
    address underlying;
    bytes6 public baseOne = 0x6d1caec02cbf;
    bytes6 public baseTwo = 0x8a4fee8b848e;
    ICauldron internal cauldron;
    IJoin ethJoin = IJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0);
    IJoin daiJoin = IJoin(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc);
    IJoin usdcJoin = IJoin(0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4);
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
            slope1: 40000 ,
            slope2: 3000000 ,
            join: ethJoin
        });
    InterestRateParameter internal daiParameters =
        InterestRateParameter({
            optimalUsageRate: 900000,
            accumulated: 1000000000000000000,
            lastUpdated: block.timestamp,
            baseVariableBorrowRate: 0,
            slope1: 40000 ,
            slope2: 600000 ,
            join: daiJoin
        });
    InterestRateParameter internal usdcParameters =
        InterestRateParameter({
            optimalUsageRate: 450000,
            accumulated: 1000000,
            lastUpdated: block.timestamp,
            baseVariableBorrowRate: 0,
            slope1: 40000 ,
            slope2: 3000000 ,
            join: usdcJoin
        });

    function setUpMock() public {
        cauldron = ICauldron(Mocks.mock("Cauldron"));
        accumulator = new VariableInterestRateOracle(cauldron);
        accumulator.grantRole(accumulator.setSource.selector, address(this));
        accumulator.grantRole(
            accumulator.updateParameters.selector,
            address(this)
        );

        baseOne = 0x6d1caec02cbf;
        baseTwo = 0x8a4fee8b848e;
    }

    function setUpHarness(string memory network) public {
        timelock = addresses[network][TIMELOCK];

        accumulator = new VariableInterestRateOracle(
            ICauldron(addresses[network][CAULDRON])
        );
        baseOne = bytes6(0x303100000000);
        underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        // vm.startPrank(timelock);
        accumulator.grantRole(accumulator.setSource.selector, address(this));
        accumulator.grantRole(
            accumulator.updateParameters.selector,
            address(this)
        );
        // vm.stopPrank();
    }

    function setUp() public virtual {
        vm.createSelectFork(MAINNET, 16877055);
        // accumulator = new VariableInterestRateOracle(
        //     ICauldron(addresses[MAINNET][CAULDRON])
        // );
        // string memory rpc = vm.envOr(RPC, MAINNET);
        // vm.createSelectFork(rpc);
        // string memory network = vm.envOr(NETWORK, LOCALHOST);
        // setUpMock();
        // if (vm.envOr(MOCK, true)) setUpMock();
        // else
        setUpHarness("MAINNET");
    }
}

abstract contract WithSourceSet is ZeroState {
    function setUp() public override {
        super.setUp();
        accumulator.setSource(
            baseOne,
            RATE,
            daiParameters.optimalUsageRate,
            daiParameters.accumulated,
            daiParameters.baseVariableBorrowRate,
            daiParameters.slope1,
            daiParameters.slope2,
            daiParameters.join
        );
    }
}

contract AccumulatorOracleTest is ZeroState {
    function testSetSourceOnlyOnce() public {
        accumulator.setSource(
            baseOne,
            RATE,
            daiParameters.optimalUsageRate,
            daiParameters.accumulated,
            daiParameters.baseVariableBorrowRate,
            daiParameters.slope1,
            daiParameters.slope2,
            daiParameters.join
        );
        vm.expectRevert("Source is already set");
        accumulator.setSource(
            baseOne,
            RATE,
            daiParameters.optimalUsageRate,
            daiParameters.accumulated,
            daiParameters.baseVariableBorrowRate,
            daiParameters.slope1,
            daiParameters.slope2,
            daiParameters.join
        );
    }

    function testCannotCallUninitializedSource() public {
        vm.expectRevert("Source not found");
        accumulator.updateParameters(
            baseOne,
            RATE,
            daiParameters.optimalUsageRate,
            daiParameters.baseVariableBorrowRate,
            daiParameters.slope1,
            daiParameters.slope2,
            daiParameters.join
        );
    }

    function testCannotCallStaleInterestRateParameter() public {
        accumulator.setSource(
            baseOne,
            RATE,
            daiParameters.optimalUsageRate,
            daiParameters.accumulated,
            daiParameters.baseVariableBorrowRate,
            daiParameters.slope1,
            daiParameters.slope2,
            daiParameters.join
        );
        skip(100);
        vm.expectRevert("stale InterestRateParameter");
        accumulator.updateParameters(
            baseOne,
            RATE,
            daiParameters.optimalUsageRate,
            daiParameters.baseVariableBorrowRate,
            daiParameters.slope1,
            daiParameters.slope2,
            daiParameters.join
        );
    }

    function testRevertOnSourceUnknown() public {
        accumulator.setSource(
            baseOne,
            RATE,
            daiParameters.optimalUsageRate,
            daiParameters.accumulated,
            daiParameters.baseVariableBorrowRate,
            daiParameters.slope1,
            daiParameters.slope2,
            daiParameters.join
        );
        vm.expectRevert("Source not found");
        accumulator.peek(bytes32(baseTwo), RATE, WAD);
        vm.expectRevert("Source not found");
        accumulator.peek(bytes32(baseOne), CHI, WAD);
    }

    // function testDoesNotMixUpSources() public {
    //     accumulator.setSource(
    //         baseOne,
    //         RATE,
    //         daiParameters.optimalUsageRate,
    //         daiParameters.baseVariableBorrowRate,
    //         daiParameters.slope1,
    //         daiParameters.slope2,
    //         daiParameters.join
    //     );
    //     accumulator.setSource(baseOne, CHI, WAD * 2, WAD);
    //     accumulator.setSource(baseTwo, RATE, WAD * 3, WAD);
    //     accumulator.setSource(baseTwo, CHI, WAD * 4, WAD);

    //     uint256 amount;
    //     (amount, ) = accumulator.peek(bytes32(baseOne), RATE, WAD);
    //     assertEq(amount, WAD, "Conversion unsuccessful");
    //     (amount, ) = accumulator.peek(bytes32(baseOne), CHI, WAD);
    //     assertEq(amount, WAD * 2, "Conversion unsuccessful");
    //     (amount, ) = accumulator.peek(bytes32(baseTwo), RATE, WAD);
    //     assertEq(amount, WAD * 3, "Conversion unsuccessful");
    //     (amount, ) = accumulator.peek(bytes32(baseTwo), CHI, WAD);
    //     assertEq(amount, WAD * 4, "Conversion unsuccessful");
    // }
}

contract WithSourceSetTest is WithSourceSet {
    function testComputesWithoutCheckpoints() public {
        uint256 amount;
        (amount, ) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        skip(10);
        (amount, ) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        skip(2);
        (amount, ) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
    }

    function testComputesWithCheckpointing() public {
        uint256 amount;
        vm.roll(block.number + 1);
        skip(1);
        (amount, ) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        vm.roll(block.number + 1);
        skip(10);
        (amount, ) = accumulator.get(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
    }

    function testUpdatesPeek() public {
        uint256 amount;
        skip(10);
        (amount, ) = accumulator.peek(bytes32(baseOne), RATE, WAD);
        assertEq(amount, WAD, "Conversion unsuccessful");
        vm.roll(block.number + 1);
        accumulator.get(bytes32(baseOne), RATE, WAD);
        (amount, ) = accumulator.peek(bytes32(baseOne), RATE, WAD);
    }
}
