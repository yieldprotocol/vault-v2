ARBITRUM_FYTOKENS=(\
    
)

MAINNET_FYTOKENS=(\

)

export NETWORK="MAINNET"
export MOCK=false

for fytoken in ${MAINNET_FYTOKENS[@]}; do
    echo "fyToken: " $fytoken
    FYTOKEN=$fytoken forge test --match-path contracts/test/fyToken/fyToken.t.sol
done 
