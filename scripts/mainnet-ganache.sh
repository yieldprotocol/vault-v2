#!/usr/bin/env sh

# move to subfolder
# cd scripts

# create db directory
# [ ! -d "./db_ganache" ] && mkdir db_ganache

# start ganache
npx ganache-cli \
    --mnemonic "how are you gentlemen all your mnemonic are belong to us" \
    --defaultBalanceEther 1000000 \
    --gasLimit 0xfffffffffff \
    --gasPrice 0 \
    --port 8545 \
    --networkId 1 \
    --host 0.0.0.0 \
    --fork https://mainnet.infura.io/v3/`cat .infuraKey` &
