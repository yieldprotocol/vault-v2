ARBITRUM_ORACLE=(\

)

MAINNET_ORACLE=(\
    "0x53FBa816BD69a7f2a096f58687f87dd3020d0d5c"\
)

export CI=false
export RPC="HARNESS"
export NETWORK="MAINNET"
export MOCK=false

for oracle in ${MAINNET_ORACLE[@]}; do
    echo "compoundMultiOracle: " $oracle
    ORACLE=$oracle forge test -c contracts/test/oracles/RateChiMultiOracle.t.sol
done 