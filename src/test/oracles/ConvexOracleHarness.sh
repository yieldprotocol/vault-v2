MAINNET_ORACLE="0x52e860327bCc464014259A7cD16DaA5763d7Dc99"

MAINNET_BASES=(\
    ["0x303000000000"]="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    ["0x313000000000"]="0x30D9410ED1D5DA1F6C8391af5338C93ab8d4035C"
)

export CI=false
export RPC="MAINNET"
export NETWORK="MAINNET"
export MOCK=false

for base in ${!MAINNET_BASES[@]}; do
    for quote in ${!MAINNET_BASES[@]}; do 
        if [ $base -ne $quote ]; then 
            echo     "Convex Oracle:  " $MAINNET_ORACLE
            printf   "Base:            %x\n" $base
            printf   "Quote:           %x\n" $quote
            echo     "Base Address:   " ${MAINNET_BASES[$base]}
            echo     "Quote Address:  " ${MAINNET_BASES[$quote]}
            ORACLE=$MAINNET_ORACLE \
            BASE=$(printf "%x" $base) \
            QUOTE=$(printf "%x" $quote) \
            BASE_ADDRESS=${MAINNET_BASES[$base]} \
            QUOTE_ADDRESS=${MAINNET_BASES[$quote]} \
            forge test -c contracts/test/oracles/ConvexOracle.t.sol -m testConversionHarness
        fi
    done
done 