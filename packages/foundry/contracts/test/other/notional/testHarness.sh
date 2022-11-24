#!/bin/bash
# Loop through the following addresses, and run the NotionalJoinHarness.t.sol tests for each one.
strategies=(\
  "0xa6624D8CF4A1Ba950d380D1e38A2D5261b711145"\
  "0xa9d104c4e020087944332632a8c5b451885fba4a"\
  "0x3FdDa15EccEE67248048a560ab61Dd2CdBDeA5E6"\
  "0xE6A63e2166fcEeB447BFB1c0f4f398083214b7aB"\
  "0xA9078E573EC536c4066A5E89F715553Ed67B13E0"\
  "0x83e99A843607CfFFC97A3acA15422aC672a463eF")

for strategy in ${strategies[@]}; do
  STRATEGY=$strategy forge test --match-path contracts/test/other/notional/NotionalJoinHarness.t.sol
done