#!/bin/bash

# Add date
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')]  $1"
}

command=$1

yarn_v=$(which yarn --version)

log "Using yarn version: ${yarn_v}"

case $command in
    "lint")
    log "Running Lint"
    yarn run lint
    local _retcode=$?
    log "Yarn gave return code: $?"
    # TODO: Return the proper code
    ;;
    "test")
    log "Running Tests"
    # TODO: Add buidler
    ;;
    "ganache") #This is bug
    log "Running Ganache"
    #npx ganache-cli \
    #    # --db "db_ganache/" \
    #    --mnemonic "all your mnemonic are belong to us seed me up scotty over" \
    #    --gasLimit 0xfffffffffff \
    #    --gasPrice 0 \
    #    --port 8545 \
    #    --networkId 5777 \
    #    --host 0.0.0.0
    ;;
    *)
    ;;
esac


exit 0