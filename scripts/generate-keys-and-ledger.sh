#! /bin/bash

# ARGS
TESTNET="${1:-pickles-public}"
COMMUNITY_KEYFILE="${2:-community-keys.txt}"

WHALE_COUNT=10
FISH_COUNT=1

PATH=$PATH:./bin/

sed_extension=
if [ "$(uname)" == "Darwin" ]; then
  sed_extension="'' -e "
fi

# DIRS
mkdir -p ./keys/keysets
mkdir -p ./keys/keypairs
rm -rf ./keys/genesis && mkdir ./keys/genesis

set -eo pipefail

# ================================================================================

# WHALES
for keyset in online-whales offline-whales; do
  [[ -s "keys/keysets/${TESTNET}_${keyset}" ]] || coda-network keyset create --count $WHALE_COUNT --name "${TESTNET}_${keyset}"
done

if [[ -s "keys/testnet-keys/${TESTNET}_online-whale-keyfiles/online_whale_account_1.pub" ]]; then
echo "using existing whale keys"
else
  # Recreate the online whale keys with ones we can put in secrets
  sed -i $sed_extension 's/"publicKey":"[^"]*"/"publicKey":"PLACEHOLDER"/g' keys/keysets/${TESTNET}_online-whales
  python3 ./scripts/testnet-keys.py keys generate-online-whale-keys --count $WHALE_COUNT --output-dir $(pwd)/keys/testnet-keys/${TESTNET}_online-whale-keyfiles
fi

# Replace the whale keys with the ones generated by testnet-keys.py
for file in keys/testnet-keys/${TESTNET}_online-whale-keyfiles/*.pub; do
  sed -i $sed_extension "s/PLACEHOLDER/$(cat $file)/" keys/keysets/${TESTNET}_online-whales
done
echo "Online Whale Keyset:"
cat keys/keysets/${TESTNET}_online-whales
echo

# ================================================================================

# FISH
for keyset in online-fish offline-fish; do
  [[ -s "keys/keysets/${TESTNET}_${keyset}" ]] || coda-network keyset create --count $FISH_COUNT --name "${TESTNET}_${keyset}"
done

if [[ -s "keys/testnet-keys/${TESTNET}_online-fish-keyfiles/online_fish_account_1.pub" ]]; then
echo "using existing fish keys"
else
  # Recreate the online fish keys with ones we can put in secrets
  sed -i $sed_extension 's/"publicKey":"[^"]*"/"publicKey":"PLACEHOLDER"/g' keys/keysets/${TESTNET}_online-fish
  python3 ./scripts/testnet-keys.py keys generate-online-fish-keys --count $FISH_COUNT --output-dir $(pwd)/keys/testnet-keys/${TESTNET}_online-fish-keyfiles
fi

# Replace the fish keys with the ones generated by testnet-keys.py
for file in keys/testnet-keys/${TESTNET}_online-fish-keyfiles/*.pub; do
  sed -i $sed_extension "s/PLACEHOLDER/$(cat $file)/" keys/keysets/${TESTNET}_online-fish
done
echo "Online Fish Keyset:"
cat keys/keysets/${TESTNET}_online-fish
echo

# ================================================================================

# COMMUNITY
declare -a PUBKEYS
read -ra PUBKEYS <<< $(tr '\n' ' ' < $COMMUNITY_KEYFILE)
COMMUNITY_SIZE=${#PUBKEYS[@]}
echo "Generating $COMMUNITY_SIZE community keys..."

for keyset in online-community offline-community; do
  [[ -s "keys/keysets/${TESTNET}_${keyset}" ]] || coda-network keyset create --count ${COMMUNITY_SIZE} --name "${TESTNET}_${keyset}"
done

if [[ -s "keys/testnet-keys/${TESTNET}_online-community" ]]; then
echo "using existing community keys"
else
  sed -i $sed_extension 's/"publicKey":"[^"]*"/"publicKey":"PLACEHOLDER"/g' keys/keysets/${TESTNET}_online-community
fi

# Replace the community keys with the ones from community-keys.txt
for key in ${PUBKEYS[@]}; do
  sed -i $sed_extension "s/PLACEHOLDER/$key/" keys/keysets/${TESTNET}_online-community
done
echo "Online Community Keyset:"
cat keys/keysets/${TESTNET}_online-community
echo

# ================================================================================

# SERVICES
[[ -s "keys/keysets/${TESTNET}_online-service-keys" ]] || coda-network keyset create --count 2 --name ${TESTNET}_online-service-keys

# ================================================================================

# GENESIS
if [[ -s "terraform/testnets/${TESTNET}/genesis_ledger.json" ]] ; then
  echo "-- genesis_ledger.json already exists for this testnet, refusing to overwrite. Delete \'terraform/testnets/${TESTNET}/genesis_ledger.json\' to force re-creation."
else
  echo "-- Generated the following keypairs and keysets for use in ./bin/coda-network genesis --"
  ls -R ./keys

  PROMPT_KEYSETS="${TESTNET}_online-community
65000
${TESTNET}_online-community
y
${TESTNET}_offline-whales
80000
${TESTNET}_online-whales
y
${TESTNET}_offline-fish
1000
${TESTNET}_online-fish
y
${TESTNET}_online-service-keys
50000
${TESTNET}_online-service-keys
n
"

  while read input
  do echo "$input"
    sleep 1
  done < <(echo -n "$PROMPT_KEYSETS") | coda-network genesis

  if [ "$(uname)" == "Darwin" ]; then
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  else
    TIMESTAMP=$(date --utc --rfc-3339=seconds | sed "s/ /T/")
  fi

  # Fix the ledger format for ease of use
  echo "Rewriting ./keys/genesis/* as terraform/testnets/${TESTNET}/genesis_ledger.json in the proper format for daemon consumption..."
  cat ./keys/genesis/* | jq '.[] | select(.balance=="80000") | . + { sk: null, delegate: .delegate, balance: (.balance + ".000000000") }' | cat > terraform/testnets/${TESTNET}/whales.json
  cat ./keys/genesis/* | jq '.[] | select(.balance=="1000") | . + { sk: null, delegate: .delegate, balance: (.balance + ".000000000") }' | cat > terraform/testnets/${TESTNET}/fish.json
  cat ./keys/genesis/* | jq '.[] | select(.balance=="65000") | . + { sk: null, delegate: .delegate, balance: (.balance + ".000000000"), timing: { initial_minimum_balance: "50000", cliff_time:"150", vesting_period:"3", vesting_increment:"300"}}' | cat > terraform/testnets/${TESTNET}/community_locked_keys.json
  jq -s '{ genesis: { genesis_state_timestamp: "'${TIMESTAMP}'" }, ledger: { name: "'${TESTNET}'", num_accounts: 100, accounts: [ .[] ] } }' terraform/testnets/${TESTNET}/*.json > terraform/testnets/${TESTNET}/genesis_ledger.json
fi

echo "Keys and genesis ledger generated successfully, $TESTNET is ready to deploy!"
