#!/usr/bin/env sh

# move to subfolder
cd scripts

# create db directory
[ ! -d "./db_ganache" ] && mkdir db_ganache

# start ganache
npx ganache-cli \
    --db "db_ganache/" \
    --mnemonic "width whip dream dress captain vessel mix drive oxygen broken soap bone" \
    --gasLimit 0xfffffffffff \
    --gasPrice 0 \
    --port 8545 \
    --networkId 5777 \
    --host 0.0.0.0
