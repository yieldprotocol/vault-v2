MAINNET_ORACLE=(\
    "0x53FBa816BD69a7f2a096f58687f87dd3020d0d5c"\
)

MAINNET_BASES=(\
    ["0x303000000000"]="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    ["0x303100000000"]="0x6B175474E89094C44Da98b954EedeAC495271d0F"
    ["0x303200000000"]="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
    ["0x313800000000"]="0x853d955aCEf822Db058eb8505911ED77F175b99e"
)

export CI=false
export RPC="MAINNET"
export NETWORK="MAINNET"
export MOCK=false

for oracle in ${MAINNET_ORACLE[@]}; do
   echo     "Oracle:    " $MAINNET_ORACLE
   printf   "Base:       %x\n" $token
   echo     "Address:   " ${MAINNET_BASES[$token]}
   ORACLE=$MAINNET_ORACLE \
   BASE=$(printf "%x" $token) \
   ADDRESS=${MAINNET_BASES[$token]} \
   forge test -c contracts/test/oracles/CompoundMultiOracle.t.sol
done 