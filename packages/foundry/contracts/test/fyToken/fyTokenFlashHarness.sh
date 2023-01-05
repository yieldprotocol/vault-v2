# addresses from June '23 series
ARBITRUM_FYTOKENS=(\
    "0x523803c57a497c3AD0E850766c8276D4864edEA5"
    "0x60a6A7fabe11ff36cbE917a17666848f0FF3A60a"\
    "0xCbB7Eba13F9E1d97B2138F588f5CA2F5167F06cc"\
)

MAINNET_FYTOKENS=(\
    "0x124c9F7E97235Fe3E35820f95D10aFfCe4bE9168"\
    "0x9ca4D6fbE0Ba91d553e74805d2E2545b04AbEfEA"\
    "0x667f185407C4CAb52aeb681f0006e4642d8091DF"\
    "0xFA71e5f0072401dA161b1FC25a9636927AF690D0"\
)

export CI=false
export RPC="ARBITRUM"
export NETWORK="ARBITRUM"
export MOCK=false

for fytoken in ${ARBITRUM_FYTOKENS[@]}; do
    echo "fyToken: " $fytoken
    FYTOKEN=$fytoken forge test -c contracts/test/fyToken/FYTokenFlash.t.sol
done 
