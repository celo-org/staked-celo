#!/usr/bin/env bash
#
# Verifies the deployed staked-CELO contracts from the sources in this repository.
#
# The production profile reproduces the build the Hardhat toolchain produced byte for
# byte, metadata trailer included (see foundry.toml and scripts/bytecode-compat-check.py),
# so a contract deployed before the move to Foundry still verifies as a full match as
# long as its source has not changed since. Run
# `python3 scripts/bytecode-compat-check.py --deployments <network>` first to see which
# implementations the current sources still reproduce.
#
# For every contract the script verifies two addresses: the implementation from
# deployments/<network>/<Name>_Implementation.json and the ERC1967 proxy in front of it
# from deployments/<network>/<Name>_Proxy.json.
#
# Both can have constructor arguments - the proxy always takes the implementation address
# and the initializer calldata, and the MultiSig implementation takes `minDelay` - and an
# explorer only reproduces the creation code when it is given them. They are taken from
# the `args` field of the deployment record and ABI-encoded against the constructor of the
# Foundry artifact in out/. A record that carries no `args` falls back to
# --guess-constructor-args, which recovers them from the creation code on chain.
#
# Usage:
#   scripts/verify-contracts.sh [options] <network> [Contract ...]
#
#   scripts/verify-contracts.sh --dry-run celo
#   scripts/verify-contracts.sh celo Manager
#   CELOSCAN_API_KEY=... scripts/verify-contracts.sh --watch celo
#
# Options:
#   --dry-run         print the forge commands instead of running them
#   --watch           wait for each submission to be processed
#   --link-libraries  compile DefaultStrategy with the AddressSortedLinkedList address in
#                     `settings.libraries`. Off by default because the contracts were
#                     deployed from an unlinked build and baking the address in changes
#                     the metadata hash; only use it for a verifier that cannot resolve
#                     library placeholders from the deployed code itself.
#   -h, --help        this text
#
# Environment:
#   CELOSCAN_API_KEY  when set, every contract is also submitted to Celoscan. Celoscan is
#                     part of the Etherscan V2 API, so this is an etherscan.io key and it
#                     works for every chain in that API. CELO_SCAN_API_KEY (the name used
#                     by the Hardhat era .env) and ETHERSCAN_API_KEY are accepted as well.
#                     Sourcify needs no key.
#   LIBRARY_ADDRESS   AddressSortedLinkedList address, for deployment records that do not
#                     carry it.
#   CHAIN_ID          chain id override, for a network this script has no entry for.
#   ETH_RPC_URL       node to read the chain id and the proxy creation code from,
#                     overriding the built-in endpoint of the network.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROXY_CONTRACT="@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol:ERC1967Proxy"
LIBRARY_SOURCE="contracts/common/linkedlists/AddressSortedLinkedList.sol"
LIBRARY_NAME="AddressSortedLinkedList"

DRY_RUN=0
WATCH=0
LINK_LIBRARIES=0
NETWORK=""
NAMES=()
FAILED=0

usage() {
  sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed -e '$d' -e 's/^#\{0,1\} \{0,1\}//'
}

die() {
  echo "error: $*" >&2
  exit 1
}

# --- arguments ---------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --watch) WATCH=1 ;;
    --link-libraries) LINK_LIBRARIES=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*) die "unknown option $1 (--help for usage)" ;;
    *)
      if [[ -z $NETWORK ]]; then
        NETWORK="$1"
      else
        NAMES+=("$1")
      fi
      ;;
  esac
  shift
done

[[ -n $NETWORK ]] || {
  usage >&2
  exit 1
}
[[ -d "deployments/$NETWORK" ]] || die "no deployments/$NETWORK directory"

# --- network -----------------------------------------------------------------

# Celoscan is served by the unified Etherscan V2 API: one host for every chain, the chain
# picked with the `chainid` query parameter. The per-explorer V1 endpoints it replaced
# (api.celoscan.io, api-alfajores.celoscan.io) were retired in August 2025 and now answer
# every request with "You are using a deprecated V1 endpoint". Forge does not append
# `chainid` to a --verifier-url it is handed, so the parameter is spelled out below.
ETHERSCAN_V2_API="https://api.etherscan.io/v2/api"

case "$NETWORK" in
  celo)
    CHAIN="42220"
    RPC_URL="https://forno.celo.org"
    HAS_EXPLORER=1
    ;;
  alfajores)
    CHAIN="44787"
    RPC_URL="https://alfajores-forno.celo-testnet.org/"
    HAS_EXPLORER=1
    ;;
  staging)
    # The staging network is not defined in legacy/hardhat.config.ts beyond its RPC URL
    # and has no public explorer, so its chain id has to come from the node or CHAIN_ID.
    CHAIN=""
    RPC_URL="https://staging-forno.celo-networks-dev.org/"
    HAS_EXPLORER=0
    ;;
  *)
    CHAIN=""
    RPC_URL=""
    HAS_EXPLORER=0
    ;;
esac

RPC_URL="${ETH_RPC_URL:-$RPC_URL}"
CHAIN="${CHAIN_ID:-$CHAIN}"
if [[ -z $CHAIN ]]; then
  [[ -n $RPC_URL ]] || die "unknown network $NETWORK; set CHAIN_ID"
  CHAIN="$(cast chain-id --rpc-url "$RPC_URL")" ||
    die "could not read the chain id of $NETWORK from $RPC_URL; set CHAIN_ID"
fi

EXPLORER_API=""
if [[ $HAS_EXPLORER -eq 1 ]]; then
  EXPLORER_API="$ETHERSCAN_V2_API?chainid=$CHAIN"
fi

API_KEY="${CELOSCAN_API_KEY:-${CELO_SCAN_API_KEY:-${ETHERSCAN_API_KEY:-}}}"
if [[ -n $API_KEY && -z $EXPLORER_API ]]; then
  echo "note: $NETWORK has no Celoscan endpoint, verifying on Sourcify only" >&2
fi

# --- deployment records ------------------------------------------------------

record_address() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("address") or "")' "$1"
}

# The constructor arguments of a deployment record, one per line. Numbers are printed in
# the decimal form `cast abi-encode` expects; nothing is printed when there are none.
record_args() {
  python3 - "$1" <<'PY'
import json, sys
for arg in json.load(open(sys.argv[1])).get("args") or []:
    print(arg if isinstance(arg, str) else json.dumps(arg))
PY
}

# The `constructor(...)` signature of a compiled contract, empty when it takes no
# arguments. Read from the Foundry artifact; the deployment records carry the values but
# not their types.
constructor_signature() {
  local artifact="out/$1.sol/$1.json"
  [[ -f $artifact ]] || die "no artifact $artifact; run forge build"
  python3 - "$artifact" <<'PY'
import json, sys


def canonical(item):
    """The ABI type of one input, with tuples spelled out as `(type,...)`."""
    kind = item["type"]
    if kind.startswith("tuple"):
        inner = ",".join(canonical(component) for component in item["components"])
        return "(%s)%s" % (inner, kind[len("tuple"):])
    return kind


for entry in json.load(open(sys.argv[1]))["abi"]:
    if entry.get("type") == "constructor" and entry.get("inputs"):
        print("constructor(%s)" % ",".join(canonical(i) for i in entry["inputs"]))
        break
PY
}

# `record_args` as an array. bash 3.2, the version macOS ships, has neither `mapfile` nor
# name references, so the result is handed over in a global.
RECORD_ARGS=()
read_record_args() {
  local line
  RECORD_ARGS=()
  while IFS= read -r line; do
    if [[ -n $line ]]; then
      RECORD_ARGS+=("$line")
    fi
  done < <(record_args "$1")
}

# AddressSortedLinkedList, from the environment, from the `libraries` map hardhat-deploy
# wrote into the DefaultStrategy record, or from the record DeployCore writes for it.
library_address() {
  if [[ -n ${LIBRARY_ADDRESS:-} ]]; then
    echo "$LIBRARY_ADDRESS"
    return
  fi
  local from_strategy
  from_strategy="$(python3 -c 'import json,sys
try: d = json.load(open(sys.argv[1]))
except OSError: d = {}
print(d.get("libraries", {}).get(sys.argv[2]) or "")' \
    "deployments/$NETWORK/DefaultStrategy_Implementation.json" "$LIBRARY_NAME")"
  if [[ -n $from_strategy ]]; then
    echo "$from_strategy"
    return
  fi
  local record="deployments/$NETWORK/${LIBRARY_NAME}_Implementation.json"
  if [[ -f $record ]]; then
    record_address "$record"
  fi
}

source_path() {
  find contracts -name "$1.sol" -not -path 'contracts/mock/*' -print -quit
}

# --- verification ------------------------------------------------------------

run_forge() {
  if [[ $DRY_RUN -eq 1 ]]; then
    printf '  '
    printf '%q ' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

# verify <address> <contract identifier> [extra forge arguments ...]
verify() {
  local address="$1" identifier="$2"
  shift 2
  local base=(forge verify-contract "$address" "$identifier" --chain "$CHAIN")
  if [[ $WATCH -eq 1 ]]; then
    base+=(--watch)
  fi
  base+=("$@")

  echo "$identifier at $address"
  if ! run_forge "${base[@]}" --verifier sourcify; then
    FAILED=1
  fi
  if [[ -n $API_KEY && -n $EXPLORER_API ]]; then
    if ! run_forge "${base[@]}" --verifier etherscan \
      --etherscan-api-key "$API_KEY" --verifier-url "$EXPLORER_API"; then
      FAILED=1
    fi
  fi
}

verify_implementation() {
  local name="$1"
  local record="deployments/$NETWORK/${name}_Implementation.json"
  [[ -f $record ]] || return 0

  local address src signature extra=()
  address="$(record_address "$record")"
  [[ -n $address ]] || die "$record has no address"
  src="$(source_path "$name")"
  [[ -n $src ]] || die "no source file for $name under contracts/"

  # Most implementations have no constructor - they are proxied, so their state comes from
  # an initializer - but MultiSig takes `minDelay`, and without it the creation code the
  # explorer recompiles does not match the one on chain.
  signature="$(constructor_signature "$name")"
  if [[ -n $signature ]]; then
    read_record_args "$record"
    if [[ ${#RECORD_ARGS[@]} -gt 0 ]]; then
      extra+=(--constructor-args "$(cast abi-encode "$signature" "${RECORD_ARGS[@]}")")
    elif [[ -n $RPC_URL ]]; then
      extra+=(--guess-constructor-args --rpc-url "$RPC_URL")
    else
      echo "warning: no constructor arguments for the $name implementation" >&2
    fi
  fi

  # Only a verifier that cannot substitute library placeholders itself needs this, and it
  # changes the metadata hash because the deployed code was compiled unlinked.
  if [[ $LINK_LIBRARIES -eq 1 && $name == "DefaultStrategy" ]]; then
    local library
    library="$(library_address)"
    [[ -n $library ]] || die "--link-libraries needs LIBRARY_ADDRESS"
    extra+=(--libraries "$LIBRARY_SOURCE:$LIBRARY_NAME:$library")
  fi

  verify "$address" "$src:$name" ${extra[@]+"${extra[@]}"}
}

verify_proxy() {
  local name="$1"
  local record="deployments/$NETWORK/${name}_Proxy.json"
  [[ -f $record ]] || return 0

  local address extra=()
  address="$(record_address "$record")"
  [[ -n $address ]] || die "$record has no address"

  read_record_args "$record"
  if [[ ${#RECORD_ARGS[@]} -eq 2 ]]; then
    extra+=(
      --constructor-args
      "$(cast abi-encode 'constructor(address,bytes)' "${RECORD_ARGS[@]}")"
    )
  elif [[ -n $RPC_URL ]]; then
    # A record from a run that predates the `args` field; recover the arguments from the
    # trailing bytes of the creation transaction instead.
    extra+=(--guess-constructor-args --rpc-url "$RPC_URL")
  else
    echo "warning: no constructor arguments for $name proxy, skipping" >&2
    return 0
  fi

  verify "$address" "$PROXY_CONTRACT" "${extra[@]}"
}

# --- run ---------------------------------------------------------------------

VERIFY_ALL=0
if [[ ${#NAMES[@]} -eq 0 ]]; then
  VERIFY_ALL=1
  for record in "deployments/$NETWORK"/*_Implementation.json; do
    NAMES+=("$(basename "$record" _Implementation.json)")
  done
fi

TARGETS="Sourcify"
if [[ -n $API_KEY && -n $EXPLORER_API ]]; then
  TARGETS="Sourcify and Celoscan"
fi
echo "network $NETWORK (chain $CHAIN), verifying on $TARGETS"
echo

for name in "${NAMES[@]}"; do
  verify_implementation "$name"
  verify_proxy "$name"
done

# The library is a contract of its own on chain. hardhat-deploy left it out of the
# records and only noted its address on DefaultStrategy, so it needs its own target.
if [[ $VERIFY_ALL -eq 1 && ! -f "deployments/$NETWORK/${LIBRARY_NAME}_Implementation.json" ]]; then
  LIBRARY="$(library_address)"
  if [[ -n $LIBRARY ]]; then
    verify "$LIBRARY" "$LIBRARY_SOURCE:$LIBRARY_NAME"
  fi
fi

exit "$FAILED"
