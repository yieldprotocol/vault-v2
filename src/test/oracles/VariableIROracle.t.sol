// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.13;

import "forge-std/src/Test.sol";
import "@yield-protocol/utils-v2/src/token/IERC20Metadata.sol";
import "@yield-protocol/utils-v2/src/utils/Math.sol";
import "../../oracles/VariableInterestRateOracle.sol";
import "../../variable/interfaces/IVRCauldron.sol";
import "../utils/TestConstants.sol";
import "../utils/Mocks.sol";

abstract contract ZeroState is Test, TestConstants {
    using Math for uint256;
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
    IVRCauldron internal cauldron;
    ILadle internal ladle;
    IJoin public ethJoin;
    IJoin public daiJoin;
    IJoin public usdcJoin;
    // IJoin fraxJoin = IJoin();
    // IJoin usdtJoin = IJoin();

    InterestRateParameter internal ethParameters =
        InterestRateParameter({
            optimalUsageRate: 450000,
            accumulated: 1000000000000000000,
            lastUpdated: block.timestamp,
            baseVariableBorrowRate: 0,
            slope1: 40000,
            slope2: 3000000,
            join: IJoin(Mocks.mock("Join")),
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
            join: IJoin(Mocks.mock("Join")),
            ilks: new bytes6[](2)
        });
    InterestRateParameter internal usdcParameters =
        InterestRateParameter({
            optimalUsageRate: 900000,
            accumulated: 1000000,
            lastUpdated: block.timestamp,
            baseVariableBorrowRate: 0,
            slope1: 40000,
            slope2: 600000,
            join: IJoin(Mocks.mock("Join")),
            ilks: new bytes6[](2)
        });

    InterestRateParameter internal sourceParameters;

    function setUpMock() public {
        usdcJoin = IJoin(Mocks.mock("Join"));
        daiJoin = IJoin(Mocks.mock("Join"));
        ethJoin = IJoin(Mocks.mock("Join"));
        cauldron = IVRCauldron(Mocks.mock("VRCauldron"));
        ladle = ILadle(Mocks.mock("Ladle"));
        variableInterestRateOracle = new VariableInterestRateOracle(
            cauldron,
            ladle
        );

        // Setting permissions
        variableInterestRateOracle.grantRole(
            variableInterestRateOracle.setSource.selector,
            address(this)
        );
        variableInterestRateOracle.grantRole(
            variableInterestRateOracle.updateParameters.selector,
            address(this)
        );

        baseOne = DAI;
        baseTwo = 0x8a4fee8b848e;

        // Mocking debts
        DataTypes.Debt memory debt = DataTypes.Debt({
            max: 0,
            min: 0,
            dec: 0,
            sum: 10000e18 // Used by oracle
        });
        cauldron.debt.mock(baseOne, baseOne, debt);
        for (uint256 i = 0; i < sourceParameters.ilks.length; i++) {
            cauldron.debt.mock(baseOne, sourceParameters.ilks[i], debt);
            cauldron.ilks.mock(baseOne, sourceParameters.ilks[i], true);
        }

        //Mocking Joins and balances
        ladle.joins.mock(USDC, usdcJoin);
        ladle.joins.mock(ETH, ethJoin);
        ladle.joins.mock(DAI, daiJoin);

        usdcJoin.storedBalance.mock(500000e6);
        daiJoin.storedBalance.mock(500000e18);
        ethJoin.storedBalance.mock(100000e18);
    }

    function setUpHarness(string memory network) public {
        vm.createSelectFork(MAINNET, 16877055);
        ethJoin = IJoin(0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0);
        daiJoin = IJoin(0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc);
        usdcJoin = IJoin(0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4);
        timelock = addresses[network][TIMELOCK];

        variableInterestRateOracle = new VariableInterestRateOracle(
            IVRCauldron(addresses[network][CAULDRON]),
            ILadle(addresses[network][LADLE])
        );

        baseOne = bytes6(0x303100000000);
        underlying = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        variableInterestRateOracle.grantRole(
            variableInterestRateOracle.setSource.selector,
            address(this)
        );
        variableInterestRateOracle.grantRole(
            variableInterestRateOracle.updateParameters.selector,
            address(this)
        );
    }

    function setUp() public virtual {
        sourceParameters = daiParameters;
        sourceParameters.ilks[0] = USDC;
        sourceParameters.ilks[1] = ETH;
        setUpMock();
    }

    function getAccumulation(
        uint totalDebt,
        uint totalLiquidity,
        uint secondsSinceLastUpdate,
        bytes6 base
    ) internal returns (uint) {
        (
            uint256 accumulated,
            uint256 lastUpdated,
            uint256 optimalUsageRate,
            uint256 baseVariableBorrowRate,
            uint256 slope1,
            uint256 slope2,
            IJoin join
        ) = variableInterestRateOracle.sources(base, RATE);

        uint256 utilizationRate = uint256(totalDebt).wdiv(totalLiquidity);
        uint256 interestRate;
        if (utilizationRate <= optimalUsageRate) {
            interestRate =
                baseVariableBorrowRate +
                utilizationRate.wmul(slope1).wdiv(
                    optimalUsageRate
                );
        } else {
            interestRate =
                baseVariableBorrowRate +
                slope1 +
                (utilizationRate - optimalUsageRate)
                    .wmul(slope2)
                    .wdiv(1e18 - optimalUsageRate);
        }
        // Calculate per second rate
        interestRate = interestRate / 365 days;
        accumulated *= (1e18 + interestRate).wpow(
            secondsSinceLastUpdate
        );
        accumulated /= 1e18;
        lastUpdated = block.timestamp;
        return accumulated;
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
            sourceParameters.slope2
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
            sourceParameters.slope2
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
            sourceParameters.ilks
        );
        vm.expectRevert("Source not found");
        variableInterestRateOracle.peek(bytes32(baseTwo), RATE, WAD);
        vm.expectRevert("Source not found");
        variableInterestRateOracle.peek(bytes32(baseOne), CHI, WAD);
    }
}

contract WithSourceSetTest is WithSourceSet {
    function testComputesWithoutCheckpoints() public {
        uint256 amount;
        (amount, ) = variableInterestRateOracle.get(bytes32(baseOne), RATE, 0);
        assertEq(amount, WAD, "Conversion unsuccessful");
        skip(10);

        uint accum = getAccumulation(
            30000e18,
            500000e18,
            10,
            baseOne
        );
        (amount, ) = variableInterestRateOracle.get(bytes32(baseOne), RATE, 0);
        assertEq(amount, accum, "Conversion unsuccessful");
        skip(365 days);

        (accum) = getAccumulation(
            30000e18,
            500000e18,
            365 days,
            baseOne
        );
        (amount, ) = variableInterestRateOracle.get(bytes32(baseOne), RATE, 0);
        assertEq(amount, accum, "Conversion unsuccessful");
    }

    function testComputesWithCheckpointing() public {
        uint256 amount;
        vm.roll(block.number + 1);
        skip(1);
        uint accum = getAccumulation(
            30000e18,
            500000e18,
            1,
            baseOne
        );
        (amount, ) = variableInterestRateOracle.get(bytes32(baseOne), RATE, 0);
        assertEq(amount, accum, "Conversion unsuccessful");
        vm.roll(block.number + 1);
        skip(10);
        accum = getAccumulation(
            30000e18,
            500000e18,
            10,
            baseOne
        );
        (amount, ) = variableInterestRateOracle.get(bytes32(baseOne), RATE, 0);
        assertEq(amount, accum, "Conversion unsuccessful");
    }

    function testUpdatesPeek() public {
        uint256 amount;
        skip(10);
        (amount, ) = variableInterestRateOracle.peek(bytes32(baseOne), RATE, 0);
        assertEq(amount, WAD, "Conversion unsuccessful");
        vm.roll(block.number + 1);
        variableInterestRateOracle.get(bytes32(baseOne), RATE, 0);
        (amount, ) = variableInterestRateOracle.peek(bytes32(baseOne), RATE, 0);
    }
}
