#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lab12-env.sh
source "${repo_root}/scripts/lab12-env.sh"

printf '%s\n' '== Tool versions =='
spin --version
tinygo version
wasmtime --version
hyperfine --version

printf '%s\n' '== Spin component =='
(
  cd "${repo_root}/wasm"
  spin build
)

printf '%s\n' '== Standalone WASI module =='
tinygo build \
  -o "${repo_root}/wasm-cli/main.wasm" \
  -target=wasi \
  -no-debug \
  "${repo_root}/wasm-cli/main.go"

printf '%s\n' '== Artifact sizes =='
stat -c '%n %s bytes' \
  "${repo_root}/wasm/main.wasm" \
  "${repo_root}/wasm-cli/main.wasm"

printf '%s\n' '== Standalone WASI response =='
wasmtime run \
  --env REQUEST_METHOD=GET \
  --env PATH_INFO=/time \
  "${repo_root}/wasm-cli/main.wasm"
