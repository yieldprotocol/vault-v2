ARBITRUM_FYTOKENS=(\
    
)

# addresses from https://dashboard.tenderly.co/Yield/v2/fork/78da602e-78a8-4705-b73c-3c62991231aa/contracts
MAINNET_FYTOKENS=(\
    "0x08bfc0437b795e1d0ee4e9489fa3f447385bb1f0"\
    "0x7194d7ba2df221f369e95e7b1c109123054b3ac2"\
    "0x2058435d65698b1cd6b06b1edb58b31a0155fa7b"\
    "0x2ac3f3d6baeda36c28f058b5eb1038bb7bb872ab"\
)

export NETWORK="TENDERLY"
export MOCK=false

for fytoken in ${MAINNET_FYTOKENS[@]}; do
    echo "fyToken: " $fytoken
    FYTOKEN=$fytoken forge test -c contracts/test/fyToken/FYToken.t.sol -m testWithdrawWithZeroAmount
done 
