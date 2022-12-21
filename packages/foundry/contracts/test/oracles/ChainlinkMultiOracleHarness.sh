ARBITRUM_ORACLE=(\

)

MAINNET_ORACLE=(\
    "0xcDCe5C87f691058B61f3A65913f1a3cBCbAd9F52"\
)

export CI=false
export RPC="HARNESS"
export NETWORK="MAINNET"
export MOCK=false

for oracle in ${MAINNET_ORACLE[@]}; do
    echo "chainlinkMultiOracle: " $oracle
    ORACLE=$oracle forge test -c contracts/test/oracles/ChainlinkMultiOracle.t.sol
done 