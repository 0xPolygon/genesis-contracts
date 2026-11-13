#!/usr/bin/env bash

# Prints the StateReceiver runtime bytecode for a bor BlockAlloc code swap, with immutables filled in.
# Deploys on a throwaway anvil so solc places the immutables itself.
#
# Usage:
# scripts/state-receiver-bytecode.sh <rootSetter> <gasOracle>
# scripts/state-receiver-bytecode.sh --legacy <rootSetter>   # code live since Ahmedabad, to check the toolchain
#
# Mainnet rootSetter 0xeb1cd9e44ab6bfe5a55ee96c468086e51b1b873a, amoy 0xbe971fef2bb60f709e1daf3e55d00914e230cd94.
# `--legacy 0xeb1cd9e44ab6bfe5a55ee96c468086e51b1b873a` must print exactly `cast code 0x…1001` on mainnet.

set -euo pipefail

cd "$(dirname "$0")/.."

if [ "${1:-}" = "--legacy" ]; then
  artifact="out-fork/LegacyStateReceiver.sol/LegacyStateReceiver.json"
  args=$(cast abi-encode "constructor(address)" "$2")
else
  artifact="out-fork/StateReceiver.sol/StateReceiver.json"
  args=$(cast abi-encode "constructor(address,address)" "$1" "$2")
fi

FOUNDRY_PROFILE=fork forge build contracts/StateReceiver.sol test/helpers/LegacyStateReceiver.sol >&2

port=8599
anvil --port "$port" --silent &
anvil_pid=$!
trap 'kill "$anvil_pid"' EXIT
until cast block-number --rpc-url "http://127.0.0.1:$port" >/dev/null 2>&1; do sleep 0.2; done

# anvil's first default account
key=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
initcode="$(jq -r .bytecode.object "$artifact")${args#0x}"
address=$(cast send --rpc-url "http://127.0.0.1:$port" --private-key "$key" --create "$initcode" --json | jq -r .contractAddress)
cast code --rpc-url "http://127.0.0.1:$port" "$address"
