#!/usr/bin/env bash

# Derive the Ethereum address from the private key in the clipboard
derive_address() {
  if cast wallet address "$(pbpaste)" | pbcopy; then
    echo "✓ Ethereum address derived and copied to clipboard"
  fi
}

# Derive the private key from the mnemonic in the clipboard
derive_private_key() {
  if cast wallet private-key "$(pbpaste)" | pbcopy; then
    echo "✓ Private key derived and copied to clipboard"
  fi
}

# Generate a new Ethereum wallet. Defaults to 12 words.
eth_wallet() {
  local words="${1:-12}"
  if cast wallet new-mnemonic --words "$words" | pbcopy; then
    echo "✓ $words-word mnemonic generated and copied to clipboard"
  fi
}

# Copy the ABI of a contract from the out directory to the clipboard
# Example: foundry_copy_abi SablierLockup
function foundry_copy_abi() {
  if [[ -z "$1" ]]; then
    echo "Please provide a contract name"
    echo "Usage: foundry_copy_abi <ContractName>"
    return 1
  fi

  local contract_name=$1
  local out_dir="out"
  local json_path="${out_dir}/${contract_name}.sol/${contract_name}.json"

  if [[ ! -f "$json_path" ]]; then
    echo "Error: Could not find JSON file at $json_path"
    return 1
  fi

  # Clipboard copy
  jq -r '.abi' "$json_path" | pbcopy

  echo "ABI for $contract_name has been copied to clipboard"
}

# Zip the ABIs of the given contracts into a single ZIP file
# Example: foundry_zip_abis SablierMerkleInstant SablierMerkleLL SablierMerkleLT
function foundry_zip_abis() {
  if [[ $# -eq 0 ]]; then
    echo "Please provide at least one contract name"
    echo "Usage: foundry_zip_abis <ContractName1> <ContractName2> ..."
    return 1
  fi

  local out_dir="out"
  local temp_dir=$(mktemp -d)
  local zip_name="contract_abis_$(date +%Y%m%d_%H%M%S).zip"
  local failed_contracts=()

  echo "Extracting ABIs for: $*"

  for contract_name in "$@"; do
    local json_path="${out_dir}/${contract_name}.sol/${contract_name}.json"

    if [[ ! -f "$json_path" ]]; then
      echo "Warning: Could not find JSON file at $json_path"
      failed_contracts+=("$contract_name")
      continue
    fi

    # Extract ABI and save to temp directory
    if jq -r '.abi' "$json_path" >"${temp_dir}/${contract_name}.json"; then
      echo "✓ Extracted ABI for $contract_name"
    else
      echo "✗ Failed to extract ABI for $contract_name"
      failed_contracts+=("$contract_name")
    fi
  done

  # Create ZIP file if we have at least one successful extraction
  if [[ "$(ls -A "$temp_dir")" ]]; then
    if (cd "$temp_dir" && zip -q "../$zip_name" -- *.json); then
      mv "${temp_dir}/../${zip_name}" "./${zip_name}"
      echo -e "\n✅ Created ZIP bundle: $zip_name"
      echo "   Contains: $(find "$temp_dir" -maxdepth 1 -name "*.json" | wc -l | tr -d ' ') ABI files"
    else
      echo "✗ Failed to create ZIP file"
      rm -rf "$temp_dir"
      return 1
    fi
  else
    echo -e "\n✗ No ABIs were successfully extracted"
    rm -rf "$temp_dir"
    return 1
  fi

  # Clean up
  rm -rf "$temp_dir"

  # Report any failures
  if [[ ${#failed_contracts[@]} -gt 0 ]]; then
    echo -e "\n⚠️  Failed to extract ABIs for: ${failed_contracts[*]}"
  fi
}

# Generate a new BIP-39 mnemonic (12/15/18/21/24 words). Defaults to 12.
mnemonic() {
  local words="${1:-12}"
  local strength
  case "$words" in
  12) strength=128 ;;
  15) strength=160 ;;
  18) strength=192 ;;
  21) strength=224 ;;
  24) strength=256 ;;
  *)
    echo "Usage: mnemonic [12|15|18|21|24]" >&2
    return 1
    ;;
  esac

  NODE_PATH="$(npm root -g)" node -e "
    const bip39 = require('bip39');
    console.log(bip39.generateMnemonic($strength));
  " | pbcopy

  echo "✓ $words-word mnemonic generated and copied to clipboard"
}

# Invoke foundry commands with custom profiles like this:
# profile optimized forge build
# See https://twitter.com/DrakeEvansV1/status/1669388194888966144
function profile() {
  FOUNDRY_PROFILE=$1 "${@:2}"
}
