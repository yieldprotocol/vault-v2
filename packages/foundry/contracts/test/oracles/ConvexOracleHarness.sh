ARBITRUM_ORACLE=(\

)

MAINNET_ORACLE=(\
    "0x52e860327bCc464014259A7cD16DaA5763d7Dc99"\
)

export CI=false
export RPC="MAINNET"
export NETWORK="MAINNET"
export MOCK=false

for oracle in ${MAINNET_ORACLE[@]}; do
    echo "cvx3CrvOracle: " $oracle
    ORACLE=$oracle forge test -c contracts/test/oracles/ConvexOracle.t.sol
done 

cvx3CrvOracle