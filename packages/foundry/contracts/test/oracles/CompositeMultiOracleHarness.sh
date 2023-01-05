ARBITRUM_ORACLE=(\

)

MAINNET_ORACLE=(\
    "0xA81414a544D0bd8a28257F4038D3D24B08Dd9Bb4"\
)

export CI=false
export RPC="MAINNET"
export NETWORK="MAINNET"
export MOCK=false

for oracle in ${MAINNET_ORACLE[@]}; do
    echo "compositeMultiOracle: " $oracle
    ORACLE=$oracle forge test -c contracts/test/oracles/CompositeMultiOracle.t.sol
done 
