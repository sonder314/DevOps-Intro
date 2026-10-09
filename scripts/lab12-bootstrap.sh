#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lab12-env.sh
source "${repo_root}/scripts/lab12-env.sh"

spin_version="3.4.0"
tinygo_version="0.41.1"
wasmtime_version="47.0.3"
hyperfine_version="1.19.0"

download_dir="${LAB12_TOOL_ROOT}/downloads"
bin_dir="${LAB12_TOOL_ROOT}/bin"
mkdir -p "${download_dir}" "${bin_dir}" \
  "${XDG_CACHE_HOME}" "${XDG_CONFIG_HOME}" "${XDG_DATA_HOME}"

download() {
  local url="$1"
  local destination="$2"
  if [[ ! -s "${destination}" ]]; then
    curl --fail --location --retry 3 --retry-delay 2 \
      --output "${destination}" "${url}"
  fi
}

spin_archive="${download_dir}/spin-v${spin_version}-linux-amd64.tar.gz"
download \
  "https://github.com/spinframework/spin/releases/download/v${spin_version}/spin-v${spin_version}-linux-amd64.tar.gz" \
  "${spin_archive}"
mkdir -p "${LAB12_TOOL_ROOT}/spin"
tar -xzf "${spin_archive}" -C "${LAB12_TOOL_ROOT}/spin"
ln -sfn "${LAB12_TOOL_ROOT}/spin/spin" "${bin_dir}/spin"

tinygo_archive="${download_dir}/tinygo${tinygo_version}.linux-amd64.tar.gz"
download \
  "https://github.com/tinygo-org/tinygo/releases/download/v${tinygo_version}/tinygo${tinygo_version}.linux-amd64.tar.gz" \
  "${tinygo_archive}"
tar -xzf "${tinygo_archive}" -C "${LAB12_TOOL_ROOT}"

wasmtime_archive="${download_dir}/wasmtime-v${wasmtime_version}-x86_64-linux.tar.xz"
download \
  "https://github.com/bytecodealliance/wasmtime/releases/download/v${wasmtime_version}/wasmtime-v${wasmtime_version}-x86_64-linux.tar.xz" \
  "${wasmtime_archive}"
printf '%s  %s\n' \
  'ca1fc56d1afc40c8782e96c297fd182a0da162f9a8f52a1e7b094e1dd648e178' \
  "${wasmtime_archive}" | sha256sum --check
mkdir -p "${LAB12_TOOL_ROOT}/wasmtime"
tar -xJf "${wasmtime_archive}" \
  -C "${LAB12_TOOL_ROOT}/wasmtime" --strip-components=1
ln -sfn "${LAB12_TOOL_ROOT}/wasmtime/wasmtime" "${bin_dir}/wasmtime"

hyperfine_archive="${download_dir}/hyperfine-v${hyperfine_version}-x86_64-unknown-linux-gnu.tar.gz"
download \
  "https://github.com/sharkdp/hyperfine/releases/download/v${hyperfine_version}/hyperfine-v${hyperfine_version}-x86_64-unknown-linux-gnu.tar.gz" \
  "${hyperfine_archive}"
mkdir -p "${LAB12_TOOL_ROOT}/hyperfine"
tar -xzf "${hyperfine_archive}" \
  -C "${LAB12_TOOL_ROOT}/hyperfine" --strip-components=1
ln -sfn "${LAB12_TOOL_ROOT}/hyperfine/hyperfine" "${bin_dir}/hyperfine"

spin templates install \
  --git https://github.com/spinframework/spin \
  --branch "v${spin_version}" \
  --upgrade

{
  spin --version
  tinygo version
  wasmtime --version
  hyperfine --version
  go version
} | tee "${LAB12_TOOL_ROOT}/versions.txt"
