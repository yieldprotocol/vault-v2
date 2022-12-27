ARBITRUM_ORACLE=(\

)

MAINNET_ORACLE=(\
    "0x95750d6F5fba4ed1cc4Dc42D2c01dFD3DB9a11eC"\
)

export CI=false
export RPC="HARNESS"
export NETWORK="MAINNET"
export MOCK=false

for oracle in ${MAINNET_ORACLE[@]}; do
    echo "accumulatorMultiOracle: " $oracle
    ORACLE=$oracle forge test -c contracts/test/oracles/AccumulatorOracle.t.sol
done 
