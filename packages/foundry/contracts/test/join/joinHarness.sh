#!/bin/bash
# Loop through the following addresses, and run the Join.t.sol tests for each one.
ARBITRUM_JOINS=(\
    "0xaf93a04d5D8D85F69AF65ED66A9717DB0796fB10"\ 
    "0xc31cce4fFA203d8F8D865b6cfaa4F36AD77E9810"\ 
    "0x1229C71482E458fa2cd51d13eB157Bd2b5D5d1Ee"\ 
)

MAINNET_JOINS=(\
    "0x3bDb887Dc46ec0E964Df89fFE2980db0121f0fD0"\ 
    "0x4fE92119CDf873Cf8826F4E6EcfD4E578E3D44Dc"\ 
    "0x0d9A1A773be5a83eEbda23bf98efB8585C3ae4f4"\ 
    "0x00De0AEFcd3069d88f85b4F18b144222eaAb92Af"\ 
    "0x5364d336c2d2391717bD366b29B6F351842D7F82"\ 
    "0xbDaBb91cDbDc252CBfF3A707819C5f7Ec2B92833"\ 
    "0x5AAfd8F0bfe3e1e6bAE781A6641096317D762969"\ 
    "0x41567f6A109f5bdE283Eb5501F21e3A0bEcbB779"\ 
)

export NETWORK="ARBITRUM"
export MOCK=false

for join in ${ARBITRUM_JOINS[@]}; do
    echo "Join: " $join
    JOIN=$join forge test --match-path contracts/test/join/Join.t.sol
done