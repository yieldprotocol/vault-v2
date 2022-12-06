#!/bin/bash
# Loop through the following addresses, and run the FlashJoin.t.sol tests for each one.

MAINNET_JOINS=(\
    "0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0"\ 
    "0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc"\ 
    "0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4"\ 
)

export NETWORK="MAINNET"
export MOCK=false

for join in ${MAINNET_JOINS[@]}; do
    echo "Join: " $join
    JOIN=$join forge test --match-path contracts/test/join/FlashJoin.t.sol
done