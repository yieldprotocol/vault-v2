// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.15;

import "forge-std/Test.sol";
import "../mocks/Mocks.sol";

import "../../oracle/PoolOracle.sol";

// "Magic" numbers are taken from the inputs/results of the test at https://github.com/yieldprotocol/vault-v2/blob/master/packages/foundry/contracts/test/oracles/PoolOracle.t.sol
contract PoolOracleTWARTest is Test {
    using Mocks for *;

    PoolOracle private oracle;
    IPool pool;

    function setUp() public {
        pool = IPool(Mocks.mock("IPool"));
        oracle = new PoolOracle(24 hours, 24, 5 minutes);
    }

    function testConfiguration() public {
        assertEq(oracle.windowSize(), 24 hours);
        assertEq(oracle.granularity(), 24);
        assertEq(oracle.periodSize(), 1 hours);
        assertEq(oracle.minTimeElapsed(), 5 minutes);
    }

    function testObservationIndexOf() public {
        // Tuesday, 22 March 2022 00:39:24
        uint256 timestamp = 1647909564;

        for (uint256 i = 0; i < 24; i++) {
            // Index matches the UTC hour for a 24hs window with 1h granularity
            assertEq(oracle.observationIndexOf(timestamp + i * 1 hours), i);
            // Index is circular
            assertEq(oracle.observationIndexOf(timestamp + ((i + 24) * 1 hours)), i);
        }
    }

    function testUpdateAndInitialise() public {
        // Tuesday, 22 March 2022 11:39:24
        uint256 timestamp = 1647949164;
        vm.warp(timestamp);
        uint256 currentCumulativeRatio = 1000;

        pool.currentCumulativeRatio.mock(currentCumulativeRatio, timestamp);
        assertTrue(oracle.updatePool(pool));

        for (uint256 i = 0; i < 23; i++) {
            (uint256 ts, uint256 ratio) = oracle.poolObservations(pool, i);
            if (i == 11) {
                // Observation is recorded according to observationIndexOf
                assertEq(ts, timestamp);
                assertEq(ratio, currentCumulativeRatio);
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

        vm.record();

        uint256 currentCumulativeRatio = 1000;
        pool.currentCumulativeRatio.mock(currentCumulativeRatio, block.timestamp);

        assertTrue(oracle.updatePool(pool));

        (uint256 ts, uint256 ratio) = oracle.poolObservations(pool, 0);
        (, bytes32[] memory writes) = vm.accesses(address(oracle));
        assertEq(ts, timestamp);
        assertEq(ratio, currentCumulativeRatio);
        // 24 writes for array initialisation + 2 slots written by the actual update
        assertEq(writes.length, 26);

        for (uint256 i = 1; i < 24; i++) {
            // Does not update before periodSize
            skip(59 minutes + 59 seconds);
            assertFalse(oracle.updatePool(pool));
            (, writes) = vm.accesses(address(oracle));
            assertEq(writes.length, 0);

            // Updates when periodSize is reached
            skip(1 seconds);

            currentCumulativeRatio++;
            pool.currentCumulativeRatio.mock(currentCumulativeRatio, block.timestamp);

            vm.expectEmit(true, true, true, true);
            emit ObservationRecorded(pool, i, PoolOracle.Observation(block.timestamp, currentCumulativeRatio));

            assertTrue(oracle.updatePool(pool));
            (ts, ratio) = oracle.poolObservations(pool, i);
            (, writes) = vm.accesses(address(oracle));
            assertEq(ts, block.timestamp);
            assertEq(ratio, currentCumulativeRatio);
            assertEq(writes.length, 2);

            // Does not update again within the same periodSize
            skip(1 seconds);
            assertFalse(oracle.updatePool(pool));
            (, writes) = vm.accesses(address(oracle));
            assertEq(writes.length, 0);

            // Make math simpler for next cycle
            rewind(1 seconds);
        }

        // Next update is written on the 0 index
        skip(1 hours);

        pool.currentCumulativeRatio.mock(currentCumulativeRatio, block.timestamp);

        assertTrue(oracle.updatePool(pool));
        (ts, ratio) = oracle.poolObservations(pool, 0);
        (, writes) = vm.accesses(address(oracle));
        assertEq(ts, block.timestamp);
        assertEq(ratio, currentCumulativeRatio);
        assertEq(writes.length, 2);
    }

    function testUpdateArray() public {
        IPool pool2 = IPool(Mocks.mock("IPool2"));

        // Tuesday, 22 March 2022 11:39:24
        uint256 timestamp = 1647949164;
        vm.warp(timestamp);
        uint256 currentCumulativeRatio = 1000;
        uint256 currentCumulativeRatio2 = 1000;

        pool.currentCumulativeRatio.mock(currentCumulativeRatio, timestamp);
        pool2.currentCumulativeRatio.mock(currentCumulativeRatio2, timestamp);

        IPool[] memory pools = new IPool[](2);
        pools[0] = pool;
        pools[1] = pool2;

        oracle.updatePools(pools);

        (uint256 ts, uint256 ratio) = oracle.poolObservations(pool, 11);
        assertEq(ts, timestamp);
        assertEq(ratio, currentCumulativeRatio);

        (ts, ratio) = oracle.poolObservations(pool2, 11);
        assertEq(ts, timestamp);
        assertEq(ratio, currentCumulativeRatio2);
    }

    function testPeek() public {
        // Saturday, 26 February 2022 10:15:28
        uint256 timestamp = 1645870528;
        vm.warp(timestamp);
        pool.currentCumulativeRatio.mock(6093535209085784059383367772965035, timestamp);
        assertTrue(oracle.updatePool(pool));

        vm.record();

        // Sunday, 27 February 2022 10:15:27 (24h after)
        vm.warp(1645956927);

        PoolOracle.Observation memory oldestObservation = oracle.getOldestObservationInWindow(pool);
        assertEq(oldestObservation.timestamp, timestamp);
        assertEq(oldestObservation.ratioCumulative, 6093535209085784059383367772965035);

        // Given a new current pool state
        pool.currentCumulativeRatio.mock(6186326784551706539983673376141507, 1645870528);

        // https://www.wolframalpha.com/input?i=%286.186326784551706539983673376-6.093535209085784059383367772%29+%2F+%281645956927+-+1645870528%29%29
        // 1.0739889983208426092929964930149654509890160765749603583374... × 10^-6
        assertEq(oracle.peek(pool), 1073988998320842609);
    }

    function testGet() public {
        // Saturday, 26 February 2022 10:15:28
        uint256 initialObservationTS = 1645870528;
        vm.warp(initialObservationTS);
        pool.currentCumulativeRatio.mock(6093535209085784059383367772965035, initialObservationTS);
        assertTrue(oracle.updatePool(pool));

        vm.record();

        // Saturday, 26 February 2022 17:15:28 (6h after)
        uint256 currentTS = 1645895728;
        vm.warp(currentTS);

        PoolOracle.Observation memory oldestObservation = oracle.getOldestObservationInWindow(pool);
        assertEq(oldestObservation.timestamp, initialObservationTS);
        assertEq(oldestObservation.ratioCumulative, 6093535209085784059383367772965035);

        // Given a new current pool state
        pool.currentCumulativeRatio.mock(6120609608080550173985092961928170, 1645895728);

        // https://www.wolframalpha.com/input?i=%286120609.608080550173985092961928170-6093535.209085784059383367772964055%29+%2F+%281645895728+-+1645870528%29%29
        // 1.0743809124907188334017932128617063492
        assertEq(oracle.get(pool), 1074380912490718833);

        // Verify writes to storage
        (, bytes32[] memory writes) = vm.accesses(address(oracle));
        // 2 writes to strage as Observation uses 2 slots
        assertEq(writes.length, 2);
        // Index 17 for 17h
        (uint256 ts, uint256 ratio) = oracle.poolObservations(pool, 17);
        assertEq(ts, currentTS);
        assertEq(ratio, 6120609608080550173985092961928170);
    }

    function testGetOldestObservationInWindow() public {
        uint256 currentCumulativeRatio = 42;

        // Saturday, 26 February 2022 07:32:48
        uint256 timestamp = 1645860768;
        vm.warp(timestamp);
        pool.currentCumulativeRatio.mock(currentCumulativeRatio, timestamp);
        assertTrue(oracle.updatePool(pool));

        // Under normal circumstances it fetches the slot 24 hours before
        skip(23 hours);

        PoolOracle.Observation memory oldestObservation = oracle.getOldestObservationInWindow(pool);
        assertEq(oldestObservation.timestamp, timestamp);
        assertEq(oldestObservation.ratioCumulative, currentCumulativeRatio);

        // On the edge case of not having values 24 hours before, it searches for the oldest available
        rewind(6 hours);
        oldestObservation = oracle.getOldestObservationInWindow(pool);
        assertEq(oldestObservation.timestamp, timestamp);
        assertEq(oldestObservation.ratioCumulative, currentCumulativeRatio);

        // If there are no values recorded for the pool it'll fail
        IPool pool2 = IPool(Mocks.mock("IPool2"));
        vm.expectRevert(abi.encodeWithSelector(PoolOracle.NoObservationsForPool.selector, pool2));
        oracle.getOldestObservationInWindow(pool2);
    }

    function testRevertOnStaleData() public {
        // Saturday, 26 February 2022 07:32:48
        vm.warp(1645860768);
        pool.currentCumulativeRatio.mock(42, block.timestamp);
        assertTrue(oracle.updatePool(pool));

        // 46 hours will result in the same index as 23 hours, but it'll be invalid data as it's older than the timeWindow
        skip(46 hours);

        // No valid observation exists
        vm.expectRevert(abi.encodeWithSelector(PoolOracle.MissingHistoricalObservation.selector, pool));
        oracle.peek(pool);

        // get will record an observation, but it'd be the only one and hence too recent
        pool.currentCumulativeRatio.mock(420, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(PoolOracle.InsufficientElapsedTime.selector, pool, 0));
        oracle.get(pool);
    }

    function testPeekDuringOldestTimeWindowFailures() public {
        // Saturday, 26 February 2022 07:32:48
        vm.warp(1645860768);

        // Oracle has only one value
        pool.currentCumulativeRatio.mock(42, block.timestamp);
        assertTrue(oracle.updatePool(pool));

        uint256 timeElapsed = 4 minutes + 59 seconds;
        skip(timeElapsed);
        vm.expectRevert(abi.encodeWithSelector(PoolOracle.InsufficientElapsedTime.selector, pool, timeElapsed));
        oracle.peek(pool);
    }

    function testPeekDuringOldestTimeWindow() public {
        // Saturday, 26 February 2022 10:15:28
        vm.warp(1645870528);

        // Oracle has only one value
        pool.currentCumulativeRatio.mock(6093535209085784059383367772965035, block.timestamp);
        assertTrue(oracle.updatePool(pool));

        // at 5 minutes or more we can safely (?) use the available observation,
        // Saturday, 26 February 2022 10:20:28
        skip(5 minutes);
        pool.currentCumulativeRatio.mock(6093861582613277914021074715108661, block.timestamp);

        assertEq(oracle.peek(pool), 1087911758312848792);
    }

    function testPeekMissingSlotsDuringInitialisation() public {
        uint256 initialTs = 1645860768;

        vm.warp(initialTs);
        pool.currentCumulativeRatio.mock(1e30, block.timestamp);
        assertTrue(oracle.updatePool(pool));

        // miss 1 slot
        vm.warp(initialTs + 2 hours);
        pool.currentCumulativeRatio.mock(2e30, block.timestamp);
        assertTrue(oracle.updatePool(pool));

        // 2 observations were recorded
        (uint256 ts, uint256 ratio) = oracle.poolObservations(pool, 7);
        assertEq(ts, initialTs);
        assertEq(ratio, 1e30);
        (ts, ratio) = oracle.poolObservations(pool, 9);
        assertEq(ts, 1645867968);
        assertEq(ratio, 2e30);

        // current value
        pool.currentCumulativeRatio.mock(5e30, block.timestamp);

        // should use the first observation (idx 7)
        // (5e30 - 1e30) / ((1645943568 - 1645860768) * 1e9)
        vm.warp(initialTs + 23 hours);
        assertEq(oracle.peek(pool), 48309178743961352);

        // should use the second observation (idx 9)
        // (5e30 - 2e30) / (1645950768 - 1645867968)
        vm.warp(initialTs + 25 hours);
        assertEq(oracle.peek(pool), 36231884057971014);

        // missing slot, so it should use the second (next) observation (idx 9)
        // (5e30 - 2e30) / (1645947168 - 1645867968)
        vm.warp(initialTs + 24 hours);
        assertEq(oracle.peek(pool), 37878787878787878);
    }

    function testPeekMissingSlotsDuringUpdates() public {
        // Saturday, 25 February 2022 07:32:48
        uint256 initTs = 1645774368;
        for (uint256 i = initTs; i < initTs + 24 hours; i += 1 hours) {
            vm.warp(i);
            pool.currentCumulativeRatio.mock(1, block.timestamp);
            assertTrue(oracle.updatePool(pool));
        }

        // Saturday, 26 February 2022 07:32:48
        uint256 initialTs = 1645860768;

        vm.warp(initialTs);
        pool.currentCumulativeRatio.mock(1e30, block.timestamp);
        assertTrue(oracle.updatePool(pool));

        // miss 1 slot
        vm.warp(initialTs + 2 hours);
        pool.currentCumulativeRatio.mock(2e30, block.timestamp);
        assertTrue(oracle.updatePool(pool));

        // 2 observations were recorded
        (uint256 ts, uint256 ratio) = oracle.poolObservations(pool, 7);
        assertEq(ts, initialTs);
        assertEq(ratio, 1e30);
        (ts, ratio) = oracle.poolObservations(pool, 9);
        assertEq(ts, 1645867968);
        assertEq(ratio, 2e30);

        // current value
        pool.currentCumulativeRatio.mock(5e30, block.timestamp);

        vm.record();

        // should use the first observation (idx 7)
        // (5e30 - 1e30) / ((1645943568 - 1645860768) * 1e9)
        vm.warp(initialTs + 23 hours);
        assertEq(oracle.peek(pool), 48309178743961352);
        // Verify reads to storage
        (bytes32[] memory reads, ) = vm.accesses(address(oracle));
        // 1) length for loop
        // 2) length for bound check (maybe use assembly to remove this?)
        // 3) slot 1 of Observation
        // 4) slot 2 of Observation
        assertEq(reads.length, 4);

        // should use the second observation (idx 9)
        // (5e30 - 2e30) / (1645950768 - 1645867968)
        vm.warp(initialTs + 25 hours);
        assertEq(oracle.peek(pool), 36231884057971014);
        // Verify reads to storage
        (reads, ) = vm.accesses(address(oracle));
        // 1) length for loop
        // 2) length for bound check (maybe use assembly to remove this?)
        // 3) slot 1 of Observation
        // 4) slot 2 of Observation
        assertEq(reads.length, 4);

        // missing slot, so it should use the second (next) observation (idx 9)
        // (5e30 - 2e30) / (1645947168 - 1645867968)
        vm.warp(initialTs + 24 hours);
        assertEq(oracle.peek(pool), 37878787878787878);
        // Verify reads to storage
        (reads, ) = vm.accesses(address(oracle));
        // 1) length for loop
        // 2) length for bound check (maybe use assembly to remove this?)
        // 3) slot 1 of 1st Observation
        // 4) slot 2 of 1st Observation
        // 5) length for bound check (maybe use assembly to remove this?)
        // 6) slot 1 of 2nd Observation
        // 7) slot 2 of 2nd Observation
        assertEq(reads.length, 7);
    }

    event ObservationRecorded(IPool indexed pool, uint256 index, PoolOracle.Observation observation);
}
