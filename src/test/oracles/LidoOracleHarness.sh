MAINNET_ORACLE="0x84066CAeA6186a02ED74EBF32BF008A47CbE26AD"

MAINNET_BASES=(\
    ["0x303400000000"]="0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0"
    ["0x303500000000"]="0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84"
)

export CI=false
export RPC="MAINNET"
export NETWORK="MAINNET"
export MOCK=false

for base in ${!MAINNET_BASES[@]}; do
    for quote in ${!MAINNET_BASES[@]}; do 
        if [ $base -ne $quote ]; then 
            echo     "Lido Oracle:   " $MAINNET_ORACLE
            printf   "Base:           %x\n" $base
            printf   "Quote:          %x\n" $quote
            echo     "Base Address:  " ${MAINNET_BASES[$base]}
            echo     "Quote Address: " ${MAINNET_BASES[$quote]}
            ORACLE=$MAINNET_ORACLE \
            BASE=$(printf "%x" $base) \
            QUOTE=$(printf "%x" $quote) \
            BASE_ADDRESS=${MAINNET_BASES[$base]} \
            QUOTE_ADDRESS=${MAINNET_BASES[$quote]} \
            forge test -c contracts/test/oracles/LidoOracle.t.sol -m testConversionHarness
        fi
    done
done 