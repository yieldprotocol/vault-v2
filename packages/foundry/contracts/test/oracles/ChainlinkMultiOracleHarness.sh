ARBITRUM_ORACLE=""

MAINNET_ORACLE="0xcDCe5C87f691058B61f3A65913f1a3cBCbAd9F52"

MAINNET_BASES=(\
    ["0x303000000000"]="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    ["0x303100000000"]="0x6B175474E89094C44Da98b954EedeAC495271d0F"
    ["0x303200000000"]="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    ["0x313800000000"]="0x853d955aCEf822Db058eb8505911ED77F175b99e"
)

export CI=false
export RPC="MAINNET"
export NETWORK="MAINNET"
export MOCK=false

for base in ${!MAINNET_BASES[@]}; do
    for quote in ${!MAINNET_BASES[@]}; do 
        if [ $base -ne $quote ]; then 
            echo     "Oracle:    " $MAINNET_ORACLE
            printf   "Base:       %x\n" $base
            printf   "Quote:      %x\n" $quote
            echo     "Base Address:   " ${MAINNET_BASES[$base]}
            echo     "Quote Address:  " ${MAINNET_BASES[$quote]}
            ORACLE=$MAINNET_ORACLE \
            BASE=$(printf "%x" $base) \
            QUOTE=$(printf "%x" $quote) \
            BASE_ADDRESS=${MAINNET_BASES[$base]} \
            QUOTE_ADDRESS=${MAINNET_BASES[$quote]} \
            forge test -c contracts/test/oracles/ChainlinkMultiOracle.t.sol
        fi
    done
done 
