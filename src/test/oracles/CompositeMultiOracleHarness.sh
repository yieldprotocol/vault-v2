ARBITRUM_ORACLE="0x750B3a18115fe090Bc621F9E4B90bd442bcd02F2"

ARBITRUM_BASES=(\
    ["0x303000000000"]=""
    ["0x303100000000"]=""
    ["0x303200000000"]=""

)

MAINNET_ORACLE="0xA81414a544D0bd8a28257F4038D3D24B08Dd9Bb4"

MAINNET_BASES=(\
    # ["0x303000000000"]="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    ["0x303100000000"]="0x6B175474E89094C44Da98b954EedeAC495271d0F"
    ["0x303200000000"]="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    ["0x313800000000"]="0x853d955aCEf822Db058eb8505911ED77F175b99e"
    ["0x333800000000"]="0x3B960E47784150F5a63777201ee2B15253D713e8"
    ["0x303030390000"]="0x0FBd5ca8eE61ec921B3F61B707f1D7D64456d2d1"
    ["0x303130390000"]="0x79A6Be1Ae54153AA6Fc7e4795272c63F63B2a6DC"
    ["0x303230390000"]="0x22E1e5337C5BA769e98d732518b2128dE14b553C"
    ["0x313830390000"]="0x2eb907fb4b71390dC5CD00e6b81B7dAAcE358193"

)

export CI=false
export RPC="MAINNET"
export NETWORK="MAINNET"
export MOCK=false

for base in ${!MAINNET_BASES[@]}; do
    for quote in ${!MAINNET_BASES[@]}; do 
        if [ $base -ne $quote ]; then 
            echo     "Composite Oracle: " $MAINNET_ORACLE
            printf   "Base:              %x\n" $base
            printf   "Quote:             %x\n" $quote
            echo     "Base Address:     " ${MAINNET_BASES[$base]}
            echo     "Quote Address:    " ${MAINNET_BASES[$quote]}
            ORACLE=$MAINNET_ORACLE \
            BASE=$(printf "%x" $base) \
            QUOTE=$(printf "%x" $quote) \
            BASE_ADDRESS=${MAINNET_BASES[$base]} \
            QUOTE_ADDRESS=${MAINNET_BASES[$quote]} \
            forge test -c contracts/test/oracles/CompositeMultiOracle.t.sol -m testConversionHarness
        fi
    done
done 
