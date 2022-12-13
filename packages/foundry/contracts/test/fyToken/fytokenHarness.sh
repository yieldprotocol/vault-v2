ARBITRUM_FYTOKENS=(\
    
)

MAINNET_FYTOKENS=(\
    "0x0FBd5ca8eE61ec921B3F61B707f1D7D64456d2d1"\
)

export NETWORK="TENDERLY"
export MOCK=false

for fytoken in ${MAINNET_FYTOKENS[@]}; do
    echo "fyToken: " $fytoken
    FYTOKEN=$fytoken forge test -c contracts/test/fyToken/FYToken.t.sol
done 
