#! /bin/bash

# ARGS
TESTNET="${1:-pickles-public}"
COMMUNITY_KEYFILE="${2:-community-keys.txt}"
RESET="${3:-false}"

WHALE_COUNT=5
FISH_COUNT=1

PATH=$PATH:./bin/

SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
cd "${SCRIPTPATH}/../"

if $RESET; then
  echo "resetting keys and genesis_ledger"
  rm -rf keys/genesis keys/keysets keys/keypairs
  rm -rf terraform/testnets/${TESTNET}/*.json
fi

# DIRS
mkdir -p ./keys/keysets
mkdir -p ./keys/keypairs
rm -rf ./keys/genesis && mkdir ./keys/genesis

set -eo pipefail
set -e


# ================================================================================

# WHALES
for keyset in online-whales offline-whales; do
  [[ -s "keys/keysets/${TESTNET}_${keyset}" ]] || coda-network keyset create --count "${WHALE_COUNT}" --name "${TESTNET}_${keyset}"
done

if [[ -s "keys/testnet-keys/${TESTNET}_online-whale-keyfiles/online_whale_account_1.pub" ]]; then
echo "using existing whale keys"
else
  # Recreate the online whale keys with ones we can put in secrets
  sed -ie 's/"publicKey":"[^"]*"/"publicKey":"PLACEHOLDER"/g' "keys/keysets/${TESTNET}_online-whales"
  python3 ./scripts/testnet-keys.py keys generate-online-whale-keys --count "${WHALE_COUNT}" --output-dir "$(pwd)/keys/testnet-keys/${TESTNET}_online-whale-keyfiles"
  sleep 5 #previous script may not be waiting for all keys, for loop misses last key sometimes
fi

# Replace the whale keys with the ones generated by testnet-keys.py
for file in keys/testnet-keys/${TESTNET}_online-whale-keyfiles/*.pub; do
  sed -ie "s/PLACEHOLDER/$(cat $file)/" "keys/keysets/${TESTNET}_online-whales"
done
echo "Online Whale Keyset:"
cat "keys/keysets/${TESTNET}_online-whales"
echo

# ================================================================================

# FISH
for keyset in online-fish offline-fish; do
  [[ -s "keys/keysets/${TESTNET}_${keyset}" ]] || coda-network keyset create --count "${FISH_COUNT}" --name "${TESTNET}_${keyset}"
done

if [[ -s "keys/testnet-keys/${TESTNET}_online-fish-keyfiles/online_fish_account_1.pub" ]]; then
echo "using existing fish keys"
else
  # Recreate the online fish keys with ones we can put in secrets
  sed -ie 's/"publicKey":"[^"]*"/"publicKey":"PLACEHOLDER"/g' "keys/keysets/${TESTNET}_online-fish"
  python3 ./scripts/testnet-keys.py keys generate-online-fish-keys --count "${FISH_COUNT}" --output-dir "$(pwd)/keys/testnet-keys/${TESTNET}_online-fish-keyfiles"
  sleep 5 #previous script may not be waiting for all keys, for loop misses last key sometimes
fi

# Replace the fish keys with the ones generated by testnet-keys.py
for file in keys/testnet-keys/${TESTNET}_online-fish-keyfiles/*.pub; do
  sed -ie "s/PLACEHOLDER/$(cat $file)/" "keys/keysets/${TESTNET}_online-fish"
done

echo "Online Fish Keyset:"
cat keys/keysets/${TESTNET}_online-fish
echo

# ================================================================================

# COMMUNITY 1
declare -a PUBKEYS
read -ra PUBKEYS <<< $(tr '\n' ' ' < community-keys-1.txt)
COMMUNITY_SIZE=${#PUBKEYS[@]}
echo "Generating $COMMUNITY_SIZE community keys..."

for keyset in online-community; do
  [[ -s "keys/keysets/${TESTNET}_${keyset}" ]] || coda-network keyset create --count ${COMMUNITY_SIZE} --name "${TESTNET}_${keyset}"
done

if [[ -s "keys/testnet-keys/${TESTNET}_online-community" ]]; then
echo "using existing community keys"
else
  sed -ie 's/"publicKey":"[^"]*"/"publicKey":"PLACEHOLDER"/g' keys/keysets/${TESTNET}_online-community
fi

# Replace the community keys with the ones from community-keys.txt
for key in ${PUBKEYS[@]}; do
  sed -ie "s/PLACEHOLDER/$key/" keys/keysets/${TESTNET}_online-community
done
echo "Online Community Keyset:"
cat keys/keysets/${TESTNET}_online-community
echo

# COMMUNITY 2
declare -a PUBKEYS
read -ra PUBKEYS <<< $(tr '\n' ' ' < community-keys-2.txt)
COMMUNITY_SIZE=${#PUBKEYS[@]}
echo "Generating $COMMUNITY_SIZE community2 keys..."

for keyset in online-community2; do
  [[ -s "keys/keysets/${TESTNET}_${keyset}" ]] || coda-network keyset create --count ${COMMUNITY_SIZE} --name "${TESTNET}_${keyset}"
done

if [[ -s "keys/testnet-keys/${TESTNET}_online-community2" ]]; then
echo "using existing community keys"
else
  sed -ie 's/"publicKey":"[^"]*"/"publicKey":"PLACEHOLDER"/g' keys/keysets/${TESTNET}_online-community2
fi

# Replace the community keys with the ones from community-keys.txt
for key in ${PUBKEYS[@]}; do
  sed -ie "s/PLACEHOLDER/$key/" keys/keysets/${TESTNET}_online-community2
done
echo "Online Community 2 Keyset:"
cat keys/keysets/${TESTNET}_online-community2
echo

# ================================================================================

# SERVICES
# echo "Generating 2 service keys..."
# [[ -s "keys/keysets/${TESTNET}_online-service-keys" ]] || coda-network keyset create --count 2 --name ${TESTNET}_online-service-keys

# ================================================================================

# GENESIS
if [[ -s "terraform/testnets/${TESTNET}/genesis_ledger.json" ]] ; then
  echo "-- genesis_ledger.json already exists for this testnet, refusing to overwrite. Delete \'terraform/testnets/${TESTNET}/genesis_ledger.json\' to force re-creation."
else
  echo "-- Creating genesis ledger with 'coda-network genesis' --"

  PROMPT_KEYSETS="${TESTNET}_online-community
62000
${TESTNET}_online-community
y
${TESTNET}_online-community2
62001
${TESTNET}_online-community2
y
${TESTNET}_offline-whales
100000
${TESTNET}_online-whales
y
${TESTNET}_offline-fish
1000
${TESTNET}_online-fish
y
${TESTNET}_online-fish
9000
${TESTNET}_online-fish
n
"

#y
#${TESTNET}_online-service-keys
#50000
#${TESTNET}_online-service-keys


  # Handle passing the above keyset info into interactive 'coda-network genesis' prompts
  while read input
  do echo "$input"
    sleep 1
  done < <(echo -n "$PROMPT_KEYSETS") | coda-network genesis

  GENESIS_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  # Fix the ledger format for ease of use
  echo "Rewriting ./keys/genesis/* as terraform/testnets/${TESTNET}/genesis_ledger.json in the proper format for daemon consumption..."
  cat ./keys/genesis/* | jq '.[] | select(.balance=="100000") | . + { sk: null, delegate: .delegate, balance: (.balance + ".000000000") }' | cat > "terraform/testnets/${TESTNET}/whales.json"
  cat ./keys/genesis/* | jq '.[] | select(.balance=="9000") | . + { sk: null, delegate: .delegate, balance: (.balance + ".000000000") }' | cat > "terraform/testnets/${TESTNET}/online-fish.json"
  cat ./keys/genesis/* | jq '.[] | select(.balance=="1000") | . + { sk: null, delegate: .delegate, balance: (.balance + ".000000000") }' | cat > "terraform/testnets/${TESTNET}/offline-fish.json"
  cat ./keys/genesis/* | jq '.[] | select(.balance=="62000") | . + { sk: null, delegate: .delegate, balance: (.balance + ".000000000"), timing: { initial_minimum_balance: "60000", cliff_time:"150", vesting_period:"18", vesting_increment:"300"}}' | cat > "terraform/testnets/${TESTNET}/community_fast_locked_keys.json"
  cat ./keys/genesis/* | jq '.[] | select(.balance=="62001") | . + { sk: null, delegate: .delegate, balance: (.balance + ".000000000"), timing: { initial_minimum_balance: "30000", cliff_time:"250", vesting_period:"24", vesting_increment:"200"}}' | cat > "terraform/testnets/${TESTNET}/community_slow_locked_keys.json"
  jq -s '{ genesis: { genesis_state_timestamp: "'${GENESIS_TIMESTAMP}'" }, ledger: { name: "'${TESTNET}'", num_accounts: 89, accounts: [ .[] ] } }' terraform/testnets/${TESTNET}/*.json > "terraform/testnets/${TESTNET}/genesis_ledger.json"
fi


echo "Keys and genesis ledger generated successfully, $TESTNET is ready to deploy!"
