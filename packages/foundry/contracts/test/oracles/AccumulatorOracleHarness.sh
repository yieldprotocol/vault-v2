ARBITRUM_ORACLE="0x0ad9Ef93673B6081c0c3b753CcaaBDdd8d2e7848"

# June 23 series fyTokens
ARBITRUM_BASES=(\
    ["0x303000000000"]="0x523803c57a497c3AD0E850766c8276D4864edEA5"
    ["0x303100000000"]="0x60a6A7fabe11ff36cbE917a17666848f0FF3A60a"
    ["0x303200000000"]="0xCbB7Eba13F9E1d97B2138F588f5CA2F5167F06cc"
)

MAINNET_ORACLE="0x95750d6F5fba4ed1cc4Dc42D2c01dFD3DB9a11eC"

# June 23 series fyTokens
MAINNET_BASES=(\
    ["0x303000000000"]="0x124c9F7E97235Fe3E35820f95D10aFfCe4bE9168"
    ["0x303100000000"]="0x9ca4D6fbE0Ba91d553e74805d2E2545b04AbEfEA"
    ["0x303200000000"]="0x667f185407C4CAb52aeb681f0006e4642d8091DF"
    ["0x313800000000"]="0xFA71e5f0072401dA161b1FC25a9636927AF690D0"
)

export CI=false
export RPC="MAINNET"
export NETWORK="MAINNET"
export MOCK=false

for base in ${!MAINNET_BASES[@]}; do
    echo     "Accumulator Oracle: " $MAINNET_ORACLE
    printf   "Base:                %x\n" $base
    echo     "Address:            " ${MAINNET_BASES[$base]}
    ORACLE=$MAINNET_ORACLE \
    BASE=$(printf "%x" $base) \
    ADDRESS=${MAINNET_BASES[$base]} \
    forge test -c contracts/test/oracles/AccumulatorOracle.t.sol
done 
