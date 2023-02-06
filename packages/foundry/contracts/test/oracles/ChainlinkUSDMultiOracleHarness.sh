ARBITRUM_ORACLE="0x8E9696345632796e7D80fB341fF4a2A60aa39C89"

ARBITRUM_BASE="0x303000000000"

ARBITRUM_BASE_ADDRESS="0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"

ARBITRUM_QUOTES=(\
    ["0x303100000000"]="0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1"
    ["0x303200000000"]="0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8"
    # ["0x313800000000"]="0x17FC002b466eEc40DaE837Fc4bE5c67993ddBd6F"
)

export CI=false
export RPC="ARBITRUM"
export NETWORK="ARBITRUM"
export MOCK=false

for quote in ${!ARBITRUM_QUOTES[@]}; do 
    echo     "Chainlink Oracle:  " $ARBITRUM_ORACLE
    printf   "Base:               %x\n" $ARBITRUM_BASE
    printf   "Quote:              %x\n" $quote
    echo     "Base Address:      " ${ARBITRUM_BASE_ADDRESS}
    echo     "Quote Address:     " ${ARBITRUM_QUOTES[$quote]}
    ORACLE=$ARBITRUM_ORACLE \
    BASE=$(printf "%x" $ARBITRUM_BASE) \
    QUOTE=$(printf "%x" $quote) \
    BASE_ADDRESS=${ARBITRUM_BASE_ADDRESS} \
    QUOTE_ADDRESS=${ARBITRUM_QUOTES[$quote]} \
    forge test -c contracts/test/oracles/ChainlinkUSDMultiOracle.t.sol -m testConversionHarness
done
