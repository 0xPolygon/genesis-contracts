#!/usr/bin/env sh

# Usage: 
# generate.sh 15001 heimdall-15001

set -x #echo on

if [ -z "$1" ]
  then
    echo "Bor chain id is required first argument"
  exit 1
fi

if [ -z "$2" ]
  then
    echo "Heimdall chain id is required as second argument"
  exit 1
fi

npm install
npm run truffle:compile
git submodule init
git submodule update
cd pos-contracts
npm install
node scripts/process-templates.js --bor-chain-id $1
npm run truffle:compile
cd ..
node generate-borvalidatorset.js --bor-chain-id $1 --heimdall-chain-id $2
node generate-genesis.js --bor-chain-id $1 --heimdall-chain-id $2
