MAINNET_ORACLE="0xC597E9cA52Afc13F7F5EDdaC9e53DEF569236016"

MAINNET_BASES=(\
    ["0x303200000000"]="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    ["0x303900000000"]="0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE"
)

export CI=false
export RPC="MAINNET"
export NETWORK="MAINNET"
export MOCK=false

for base in ${!MAINNET_BASES[@]}; do
    for quote in ${!MAINNET_BASES[@]}; do 
        if [ $base -ne $quote ]; then 
            echo     "Yearn Oracle:   " $MAINNET_ORACLE
            printf   "Base:            %x\n" $base
            printf   "Quote:           %x\n" $quote
            echo     "Base Address:   " ${MAINNET_BASES[$base]}
            echo     "Quote Address:  " ${MAINNET_BASES[$quote]}
            ORACLE=$MAINNET_ORACLE \
            BASE=$(printf "%x" $base) \
            QUOTE=$(printf "%x" $quote) \
            BASE_ADDRESS=${MAINNET_BASES[$base]} \
            QUOTE_ADDRESS=${MAINNET_BASES[$quote]} \
            forge test -c contracts/test/oracles/YearnVaultMultiOracle.t.sol -m testConversionHarness
        fi
    done
done 