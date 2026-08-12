#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workflow_dir="$repository_root/.github/workflows"
actionlint_version="1.7.12"

actionlint_checksum() {
  case "$1" in
    darwin_amd64)
      echo "5b44c3bc2255115c9b69e30efc0fecdf498fdb63c5d58e17084fd5f16324c644"
      ;;
    darwin_arm64)
      echo "aba9ced2dee8d27fecca3dc7feb1a7f9a52caefa1eb46f3271ea66b6e0e6953f"
      ;;
    linux_amd64)
      echo "8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8"
      ;;
    linux_arm64)
      echo "325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6"
      ;;
    *)
      return 1
      ;;
  esac
}

install_actionlint() {
  local operating_system
  local architecture
  local platform
  local checksum
  local actual_checksum
  local archive
  local install_dir

  operating_system="$(uname -s | tr '[:upper:]' '[:lower:]')"
  architecture="$(uname -m)"
  case "$architecture" in
    x86_64)
      architecture="amd64"
      ;;
    arm64 | aarch64)
      architecture="arm64"
      ;;
  esac

  platform="${operating_system}_${architecture}"
  checksum="$(actionlint_checksum "$platform")" || {
    echo "Unsupported actionlint platform: $platform" >&2
    exit 2
  }
  install_dir="$repository_root/.dart_tool/actionlint/$actionlint_version/$platform"
  mkdir -p "$install_dir"
  if [[ -x "$install_dir/actionlint" ]]; then
    echo "$install_dir/actionlint"
    return
  fi
  archive="$install_dir/actionlint.tar.gz"

  if ! curl --fail --location --silent --show-error \
    --retry 3 --retry-all-errors --retry-delay 2 \
    "https://github.com/rhysd/actionlint/releases/download/v${actionlint_version}/actionlint_${actionlint_version}_${platform}.tar.gz" \
    --output "$archive"; then
    echo "Unable to download actionlint $actionlint_version." >&2
    return 1
  fi

  if command -v sha256sum >/dev/null; then
    actual_checksum="$(sha256sum "$archive" | awk '{print $1}')"
  else
    actual_checksum="$(shasum -a 256 "$archive" | awk '{print $1}')"
  fi
  if [[ "$actual_checksum" != "$checksum" ]]; then
    echo "actionlint archive checksum verification failed." >&2
    return 1
  fi

  if ! tar -xzf "$archive" -C "$install_dir" actionlint; then
    echo "Unable to extract actionlint $actionlint_version." >&2
    return 1
  fi
  rm -f "$archive"
  echo "$install_dir/actionlint"
}

ruby "$repository_root/.github/scripts/check_action_pins_test.rb"
ruby "$repository_root/.github/scripts/check_action_pins.rb" "$repository_root/.github"
ruby "$repository_root/.github/scripts/check_codeql_config_test.rb"

if command -v actionlint >/dev/null; then
  actionlint_binary="$(command -v actionlint)"
else
  actionlint_binary="$(install_actionlint)"
fi

cd "$repository_root"
"$actionlint_binary" -color

echo "GitHub Actions workflows are valid and immutably pinned."
