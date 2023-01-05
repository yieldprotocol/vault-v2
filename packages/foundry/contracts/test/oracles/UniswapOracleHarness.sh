ARBITRUM_ORACLE=(\

)

MAINNET_ORACLE=(\
    "0x358538ea4F52Ac15C551f88C701696f6d9b38F3C"\
)

export CI=false
export RPC="HARNESS"
export NETWORK="MAINNET"
export MOCK=false

for oracle in ${MAINNET_ORACLE[@]}; do
    echo "uniswapOracle: " $oracle
    ORACLE=$oracle forge test -c contracts/test/oracles/UniswapOracle.t.sol
done 
