#!/usr/bin/env bash
#
# Runs a command with the variables of `.env.<network>` exported.
#
# The Hardhat config loaded `.env.<network>` (dotenv) for every network but `local`;
# Forge only reads `.env` from the project root. The encrypted environment files that
# `yarn keys:decrypt` (scripts/key_placer.sh) produces keep the per-network layout, so
# deploy and task scripts are started through this wrapper:
#
#   scripts/with-env.sh celo forge script script/deploy/DeployCore.s.sol --rpc-url celo ...
#   scripts/with-env.sh sepolia forge script script/tasks/multisig/ConfirmProposal.s.sol ...
#
# `local` (or an empty network) maps to `.env`, which Forge would load on its own.
# Variables already present in the environment win over the file, so a one-off override
# such as `VALIDATOR_GROUPS= scripts/with-env.sh celo ...` still works.
#
set -euo pipefail

if [ $# -lt 2 ]; then
  echo "usage: $0 <network|local> <command> [args...]" >&2
  exit 1
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NETWORK="$1"
shift

case "$NETWORK" in
  ""|local) ENV_FILE="$ROOT/.env" ;;
  *) ENV_FILE="$ROOT/.env.$NETWORK" ;;
esac

if [ ! -f "$ENV_FILE" ]; then
  echo "$ENV_FILE not found (run 'yarn keys:decrypt' or create it from .env.example)" >&2
  exit 1
fi

# Export every KEY=value line of the file that is not already set in the environment.
# Accepts the `KEY = value` spelling of the older templates as well.
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%%#*}"
  [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
  key="${BASH_REMATCH[1]}"
  value="${BASH_REMATCH[2]}"
  value="${value%"${value##*[![:space:]]}"}"
  value="${value#\"}"; value="${value%\"}"
  value="${value#\'}"; value="${value%\'}"
  if [ -z "${!key+x}" ]; then
    export "$key=$value"
  fi
done < "$ENV_FILE"

# Forge's own dotenv loading would override nothing here: it only reads `.env`, and
# exported variables take precedence over it.
export NETWORK="${NETWORK:-$NETWORK}"
exec "$@"
