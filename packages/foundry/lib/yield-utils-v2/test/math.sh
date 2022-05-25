#!/bin/bash

set -euxo pipefail

### test/fuzz test math utils (only WPow for the moment)

# It's easy to do with dapptools (obviously), but we don't use it
# Fortunately, it easy to make it work if you have dapptools installed

# Step 1: prepare a temporary directory
TMP=$(mktemp -d -t math.XXXX)
# (don't forget to clean after yourself)
trap "rm -rf $TMP" EXIT

PROJECT_ROOT=$(dirname $0)/../

# Step 2: copy all our math libraries and tests to the temp directory
mkdir $TMP/src
cp $PROJECT_ROOT/contracts/math/*.sol $TMP/src
cp $PROJECT_ROOT/test/*.t.sol $TMP/src

# Step 3: add `ds-test` library to the temp directory and run `dapp test`
pushd $TMP
    git init -q .
    dapp install ds-test
    dapp test --fuzz-runs 1000 -v 5 "$@"
popd
