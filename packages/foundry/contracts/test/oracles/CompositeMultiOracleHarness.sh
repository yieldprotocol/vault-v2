ARBITRUM_CHAINLINK_ORACLE="0x8E9696345632796e7D80fB341fF4a2A60aa39C89"

ARBITRUM_COMPOSITE_ORACLE="0x750B3a18115fe090Bc621F9E4B90bd442bcd02F2"

ARBITRUM_BASES=(\
    # ["0x303000000000"]=""
    ["0x303100000000"]=""
    ["0x303200000000"]=""

)

MAINNET_CHAINLINK_ORACLE="0xcDCe5C87f691058B61f3A65913f1a3cBCbAd9F52"

MAINNET_COMPOSITE_ORACLE="0xA81414a544D0bd8a28257F4038D3D24B08Dd9Bb4"

MAINNET_BASES=(\
    # ["0x303000000000"]="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
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
            echo     "Chainlink Oracle: " $MAINNET_CHAINLINK_ORACLE
            echo     "Composite Oracle: " $MAINNET_COMPOSITE_ORACLE
            printf   "Base:              %x\n" $base
            printf   "Quote:             %x\n" $quote
            echo     "Base Address:     " ${MAINNET_BASES[$base]}
            echo     "Quote Address:    " ${MAINNET_BASES[$quote]}
            CHAINLINK_ORACLE=$MAINNET_CHAINLINK_ORACLE \
            COMPOSITE_ORACLE=$MAINNET_COMPOSITE_ORACLE \
            BASE=$(printf "%x" $base) \
            QUOTE=$(printf "%x" $quote) \
            BASE_ADDRESS=${MAINNET_BASES[$base]} \
            QUOTE_ADDRESS=${MAINNET_BASES[$quote]} \
            forge test -c contracts/test/oracles/CompositeMultiOracle.t.sol
        fi
    done
done 
