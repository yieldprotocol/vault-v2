MAINNET_ORACLE="0x660bB2F1De01AacA46FCD8004e852234Cf65F3fb"

MAINNET_BASES=(\
    "0x303000000000"
    "0x303100000000"
    "0x303200000000"
)

MAINNET_BASE_ADDRESSES=(\
    "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
    "0x6B175474E89094C44Da98b954EedeAC495271d0F"
    "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
)

MAINNET_FCASH=(\
    "0x40301200028b"
    "0x40311200028b"
    "0x40321200028b"
)

export CI=false
export RPC="MAINNET"
export NETWORK="MAINNET"
export MOCK=false

for i in {0..2}; do
    echo     "Notional Oracle:   " $MAINNET_ORACLE
    printf   "Base:               %x\n" ${MAINNET_BASES[$i]}
    printf   "Quote:              %x\n" ${MAINNET_FCASH[$i]}
    echo     "Base Address:      " ${MAINNET_BASE_ADDRESSES[$i]}
    ORACLE=$MAINNET_ORACLE \
    BASE=$(printf "%x" ${MAINNET_BASES[$i]}) \
    QUOTE=$(printf "%x" ${MAINNET_FCASH[$i]}) \
    BASE_ADDRESS=${MAINNET_BASE_ADDRESSES[$i]} \
    forge test -c contracts/test/oracles/NotionalMultiOracle.t.sol -m testConversionHarness
done 