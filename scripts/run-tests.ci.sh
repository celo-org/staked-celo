#!/bin/bash
set -e
trap 'jobs -p | xargs -r kill || true' EXIT
echo "Starting ganache on port 7545, logs: /tmp/test.celo-devchain.log ..."
yarn run devchain &> /tmp/test.celo-devchain.log &
yarn compile

## Check if port 7545 is now open. Timeout if no response after 1 second
## to prevent nc from waiting forever especially in CI.
while ! nc -z localhost 7545 -w 1; do
  sleep 0.1 # wait for 1/10 of the second before check again
done

yarn test
