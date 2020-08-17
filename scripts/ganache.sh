#!/usr/bin/env sh

# move to subfolder
# cd scripts

# create db directory
# [ ! -d "./db_ganache" ] && mkdir db_ganache

# start ganache
npx ganache-cli \
    --mnemonic "all your mnemonic are belong to us seed me up scotty over" \
    --defaultBalanceEther 1000000 \
    --gasLimit 0xfffffffffff \
    --gasPrice 0 \
    --port 8545 \
    --networkId 5777 \
    --host 0.0.0.0 &
