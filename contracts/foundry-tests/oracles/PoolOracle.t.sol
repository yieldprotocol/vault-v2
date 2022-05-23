// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.6;

import "../utils/Test.sol";
import "../utils/Mocks.sol";

import "../../oracles/yieldspace/PoolOracle.sol";

contract PoolOracleTest is Test {
    using Mocks for *;

    PoolOracle private sut;

    function setUp() public {
        sut = new PoolOracle(24 hours, 24, 5 minutes);
    }

    function testConfiguration() public {
        assertEq(sut.windowSize(), 24 hours);
        assertEq(sut.granularity(), 24);
        assertEq(sut.periodSize(), 1 hours);
        assertEq(sut.minTimeElapsed(), 5 minutes);
    }

    function testObservationIndexOf() public {
        // Tuesday, 22 March 2022 00:39:24
        uint256 timestamp = 1647909564;

        for (uint256 i = 0; i < 24; i++) {
            // Index matches the UTC hour for a 24hs window with 1h granularity
            assertEq(sut.observationIndexOf(timestamp + i * 1 hours), i);
            // Index is circular
            assertEq(sut.observationIndexOf(timestamp + ((i + 24) * 1 hours)), i);
        }
    }

    function testUpdateAndInitialise() public {
        // Tuesday, 22 March 2022 11:39:24
        uint256 timestamp = 1647949164;
        vm.warp(timestamp);
        address pool = Mocks.mock("IPool");

        uint256 cumulativeBalancesRatio = 1000;

        IPool(pool).cumulativeBalancesRatio.mock(cumulativeBalancesRatio);
        _poolWasUpdatedOnTheSameBlock(pool);
        sut.update(pool);

        for (uint256 i = 0; i < 23; i++) {
            (uint256 ts, uint256 ratio) = sut.poolObservations(pool, i);
            if (i == 11) {
                // Observation is recorded according to observationIndexOf
                assertEq(ts, timestamp);
                assertEq(ratio, cumulativeBalancesRatio);
            } else {
                // Observations array is initialised
                assertEq(ts, 0);
                assertEq(ratio, 0);
            }
        }
    }

    function testUpdate() public {
        // Tuesday, 22 March 2022 00:00:00
        uint256 timestamp = 1647907200;
        vm.warp(timestamp);
        address pool = Mocks.mock("IPool");

        vm.record();

        uint256 cumulativeBalancesRatio = 1000;
        IPool(pool).cumulativeBalancesRatio.mock(cumulativeBalancesRatio);
        _poolWasUpdatedOnTheSameBlock(pool);

        sut.update(pool);

        (uint256 ts, uint256 ratio) = sut.poolObservations(pool, 0);
        (, bytes32[] memory writes) = vm.accesses(address(sut));
        assertEq(ts, timestamp);
        assertEq(ratio, cumulativeBalancesRatio);
        // 24 writes for array initialisation + 2 slots written by the actual update
        assertEq(writes.length, 26);

        for (uint256 i = 1; i < 24; i++) {
            cumulativeBalancesRatio++;
            IPool(pool).cumulativeBalancesRatio.mock(cumulativeBalancesRatio);
            _poolWasUpdatedOnTheSameBlock(pool);

            // Does not update before periodSize
            skip(59 minutes + 59 seconds);
            sut.update(pool);
            (, writes) = vm.accesses(address(sut));
            assertEq(writes.length, 0);

            // Updates when periodSize is reached
            skip(1 seconds);

            vm.expectEmit(true, true, true, true);
            emit ObservationRecorded(pool, i, PoolOracle.Observation(block.timestamp, cumulativeBalancesRatio));

            sut.update(pool);
            (ts, ratio) = sut.poolObservations(pool, i);
            (, writes) = vm.accesses(address(sut));
            assertEq(ts, block.timestamp);
            assertEq(ratio, cumulativeBalancesRatio);
            assertEq(writes.length, 2);

            // Does not update again within the same periodSize
            skip(1 seconds);
            sut.update(pool);
            (, writes) = vm.accesses(address(sut));
            assertEq(writes.length, 0);

            // Make math simpler for next cycle
            rewind(1 seconds);
        }

        // Next update is written on the 0 index
        skip(1 hours);
        sut.update(pool);
        (ts, ratio) = sut.poolObservations(pool, 0);
        (, writes) = vm.accesses(address(sut));
        assertEq(ts, block.timestamp);
        assertEq(ratio, cumulativeBalancesRatio);
        assertEq(writes.length, 2);
    }

    function testPeek() public {
        address pool = Mocks.mock("IPool");

        // Saturday, 26 February 2022 10:15:28
        vm.warp(1645870528);
        IPool(pool).cumulativeBalancesRatio.mock(6081248333687398745122493757731327);
        IPool(pool).getCache.mock(1102997721918618810252394, 1199964191067551228067732, 1645859234);
        sut.update(pool);

        vm.record();

        // Sunday, 27 February 2022 10:15:27 (24h after)
        vm.warp(1645956927);

        PoolOracle.Observation memory oldestObservation = sut.getOldestObservationInWindow(pool);
        assertEq(oldestObservation.timestamp, 1645870528);
        // https://www.wolframalpha.com/input?i=6081248333687398745122493757731327+%2B+%28%28%281199964191067551228067732+*+1e27%29+%2F+1102997721918618810252394%29+*+%281645870528+-+1645859234%29%29
        // 6.09353520908578405938336777296503555592051557672491409350744... × 10^33
        assertEq(oldestObservation.ratioCumulative, 6093535209085784059383367772965035);

        IPool(pool).cumulativeBalancesRatio.mock(6177238896109883718081380861139109);
        IPool(pool).getCache.mock(1146659164970519061317333, 1231180360591421143492220, 1645948463);

        // https://www.wolframalpha.com/input?i=6177238896109883718081380861139109+%2B+%28%28%281231180360591421143492220+*+1e27%29+%2F+1146659164970519061317333%29+*+%281645956927+-+1645948463%29%29
        // 6.18632678455170653998367337614150763172612596547147924230199... × 10^33
        // https://www.wolframalpha.com/input?i=%286.186326784551706539983673376-6.093535209085784059383367772%29+%2F+%281645956927+-+1645870528%29%29
        // 1.0739889983208426092929964930149654509890160765749603583374... × 10^-6
        assertEq(sut.peek(pool), 1073988998320842609);

        (, bytes32[] memory writes) = vm.accesses(address(sut));
        assertEq(writes.length, 0);
        // Index 6 for 06h (belt and braces)
        (uint256 ts, uint256 ratio) = sut.poolObservations(pool, 6);
        assertEq(ts, 0);
        assertEq(ratio, 0);
    }

    function testGet() public {
        address pool = Mocks.mock("IPool");

        // Saturday, 26 February 2022 10:15:28
        vm.warp(1645870528);
        IPool(pool).cumulativeBalancesRatio.mock(6081248333687398745122493757731327);
        IPool(pool).getCache.mock(1102997721918618810252394, 1199964191067551228067732, 1645859234);
        sut.update(pool);

        vm.record();

        // Saturday, 26 February 2022 17:15:28 (6h after)
        vm.warp(1645895728);

        PoolOracle.Observation memory oldestObservation = sut.getOldestObservationInWindow(pool);
        assertEq(oldestObservation.timestamp, 1645870528);
        // https://www.wolframalpha.com/input?i=6081248333687398745122493757731327+%2B+%28%28%281199964191067551228067732+*+1e27%29+%2F+1102997721918618810252394%29+*+%281645870528+-+1645859234%29%29
        // 6.09353520908578405938336777296503555592051557672491409350744... × 10^33
        assertEq(oldestObservation.ratioCumulative, 6093535209085784059383367772965035);

        IPool(pool).cumulativeBalancesRatio.mock(6093861582613277914021074715108661);
        IPool(pool).getCache.mock(1145485947716596761765740, 1230501498069318499806766, 1645870828);

        // https://www.wolframalpha.com/input?i=6093861582613277914021074715108661+%2B+%28%28%281230501498069318499806766+*+1e27%29+%2F+1145485947716596761765740%29+*+%281645895728+-+1645870828%29%29
        // 6120609608080550173985092961928170
        // https://www.wolframalpha.com/input?i=%286120609.608080550173985092961928170-6093535.209085784059383367772964055%29+%2F+%281645895728+-+1645870528%29%29
        // 1.0743809124907188334017932128617063492
        assertEq(sut.get(pool), 1074380912490718833);

        (, bytes32[] memory writes) = vm.accesses(address(sut));
        assertEq(writes.length, 2);
        // Index 17 for 17h
        (uint256 ts, uint256 ratio) = sut.poolObservations(pool, 17);
        assertEq(ts, 1645895728);
        assertEq(ratio, 6120609608080550173985092961928170);
    }

    function testGetOldestObservationInWindow() public {
        address pool = Mocks.mock("IPool");

        // Saturday, 26 February 2022 07:32:48
        vm.warp(1645860768);
        IPool(pool).cumulativeBalancesRatio.mock(6081248333687398745122493757731327);
        _poolWasUpdatedOnTheSameBlock(pool);
        sut.update(pool);

        // Under normal circumstances it fetches the slot 24 hours before
        skip(23 hours);

        PoolOracle.Observation memory oldestObservation = sut.getOldestObservationInWindow(pool);
        assertEq(oldestObservation.timestamp, 1645860768);
        assertEq(oldestObservation.ratioCumulative, 6081248333687398745122493757731327);

        // On the edge case of not having values 24 hours before, it searches for the oldest available
        rewind(6 hours);
        oldestObservation = sut.getOldestObservationInWindow(pool);
        assertEq(oldestObservation.timestamp, 1645860768);
        assertEq(oldestObservation.ratioCumulative, 6081248333687398745122493757731327);

        // If there are no values recorded for the pool it'll fail
        address pool2 = Mocks.mock("IPool2");
        vm.expectRevert(abi.encodeWithSelector(PoolOracle.NoObservationsForPool.selector, pool2));
        sut.getOldestObservationInWindow(pool2);
    }

    function testRevertOnStaleData() public {
        address pool = Mocks.mock("IPool");

        // Saturday, 26 February 2022 07:32:48
        vm.warp(1645860768);
        IPool(pool).cumulativeBalancesRatio.mock(6081248333687398745122493757731327);
        _poolWasUpdatedOnTheSameBlock(pool);
        sut.update(pool);

        // 46 hours will result in the same index as 23 hours, but it'll be invalid data as it's older than the timeWindow
        skip(46 hours);

        // No valid observation exists
        vm.expectRevert(abi.encodeWithSelector(PoolOracle.MissingHistoricalObservation.selector, pool));
        sut.peek(pool);

        // get will record an observation, but it'd be the only one and hence too recent
        vm.expectRevert(abi.encodeWithSelector(PoolOracle.InsufficientElapsedTime.selector, pool, 0));
        sut.get(pool);
    }

    function testPeekDuringOldestTimeWindowFailures() public {
        address pool = Mocks.mock("IPool");

        // Saturday, 26 February 2022 07:32:48
        vm.warp(1645860768);

        // Oracle has only one value
        IPool(pool).cumulativeBalancesRatio.mock(6081248333687398745122493757731327);
        _poolWasUpdatedOnTheSameBlock(pool);
        sut.update(pool);

        uint256 timeElapsed = 4 minutes + 59 seconds;
        skip(timeElapsed);
        vm.expectRevert(abi.encodeWithSelector(PoolOracle.InsufficientElapsedTime.selector, pool, timeElapsed));
        sut.peek(pool);
    }

    function testPeekDuringOldestTimeWindow() public {
        address pool = Mocks.mock("IPool");

        // Saturday, 26 February 2022 10:15:28
        vm.warp(1645870528);

        // Oracle has only one value
        IPool(pool).cumulativeBalancesRatio.mock(6081248333687398745122493757731327);
        IPool(pool).getCache.mock(1102997721918618810252394, 1199964191067551228067732, 1645859234);
        sut.update(pool);

        // at 5 minutes or more we can safely (?) use the available observation,
        // Saturday, 26 February 2022 10:20:28
        skip(5 minutes);
        assertEq(sut.peek(pool), 1087911758312848792);
    }

    function testPeekMissingSlotsDuringInitialisation() public {
        address pool = Mocks.mock("IPool");
        // Saturday, 26 February 2022 07:32:48
        uint256 initialTs = 1645860768;

        _poolWasUpdatedOnTheSameBlock(pool);

        vm.warp(initialTs);
        IPool(pool).cumulativeBalancesRatio.mock(1e30);
        sut.update(pool);

        // miss 1 slot
        vm.warp(initialTs + 2 hours);
        IPool(pool).cumulativeBalancesRatio.mock(2e30);
        sut.update(pool);

        // 2 observations were recorded
        (uint256 ts, uint256 ratio) = sut.poolObservations(pool, 7);
        assertEq(ts, initialTs);
        assertEq(ratio, 1e30);
        (ts, ratio) = sut.poolObservations(pool, 9);
        assertEq(ts, 1645867968);
        assertEq(ratio, 2e30);

        // current value
        IPool(pool).cumulativeBalancesRatio.mock(5e30);

        // should use the first observation (idx 7)
        // (5e30 - 1e30) / ((1645943568 - 1645860768) * 1e9)
        vm.warp(initialTs + 23 hours);
        assertEq(sut.peek(pool), 48309178743961352);

        // should use the second observation (idx 9)
        // (5e30 - 2e30) / (1645950768 - 1645867968)
        vm.warp(initialTs + 25 hours);
        assertEq(sut.peek(pool), 36231884057971014);

        // missing slot, so it should use the second (next) observation (idx 9)
        // (5e30 - 2e30) / (1645947168 - 1645867968)
        vm.warp(initialTs + 24 hours);
        assertEq(sut.peek(pool), 37878787878787878);
    }

    function testPeekMissingSlotsDuringUpdates() public {
        address pool = Mocks.mock("IPool");

        _poolWasUpdatedOnTheSameBlock(pool);

        // Saturday, 25 February 2022 07:32:48
        uint256 initTs = 1645774368;
        for (uint256 i = initTs; i < initTs + 24 hours; i += 1 hours) {
            vm.warp(i);
            IPool(pool).cumulativeBalancesRatio.mock(1);
            sut.update(pool);
        }

        // Saturday, 26 February 2022 07:32:48
        uint256 initialTs = 1645860768;

        vm.warp(initialTs);
        IPool(pool).cumulativeBalancesRatio.mock(1e30);
        sut.update(pool);

        // miss 1 slot
        vm.warp(initialTs + 2 hours);
        IPool(pool).cumulativeBalancesRatio.mock(2e30);
        sut.update(pool);

        // 2 observations were recorded
        (uint256 ts, uint256 ratio) = sut.poolObservations(pool, 7);
        assertEq(ts, initialTs);
        assertEq(ratio, 1e30);
        (ts, ratio) = sut.poolObservations(pool, 9);
        assertEq(ts, 1645867968);
        assertEq(ratio, 2e30);

        // current value
        IPool(pool).cumulativeBalancesRatio.mock(5e30);

        // should use the first observation (idx 7)
        // (5e30 - 1e30) / ((1645943568 - 1645860768) * 1e9)
        vm.warp(initialTs + 23 hours);
        assertEq(sut.peek(pool), 48309178743961352);

        // should use the second observation (idx 9)
        // (5e30 - 2e30) / (1645950768 - 1645867968)
        vm.warp(initialTs + 25 hours);
        assertEq(sut.peek(pool), 36231884057971014);

        // missing slot, so it should use the second (next) observation (idx 9)
        // (5e30 - 2e30) / (1645947168 - 1645867968)
        vm.warp(initialTs + 24 hours);
        assertEq(sut.peek(pool), 37878787878787878);
    }

    function _poolWasUpdatedOnTheSameBlock(address pool) internal {
        IPool(pool).getCache.mock(1, 0, 0);
    }

    event ObservationRecorded(address indexed pool, uint256 index, PoolOracle.Observation observation);
}
