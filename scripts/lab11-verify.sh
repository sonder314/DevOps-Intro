#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
evidence_dir="${repo_root}/.goenv/lab11"
mkdir -p "${evidence_dir}"
cd "${repo_root}"

echo "== Flake checks =="
nix flake check --print-build-logs

echo "== QuickNotes build A =="
nix build .#quicknotes --print-build-logs
quicknotes_store_a="$(readlink -f result)"
quicknotes_hash_a="$(nix-store --query --hash "${quicknotes_store_a}")"
printf 'store_a=%s\nhash_a=%s\n' "${quicknotes_store_a}" "${quicknotes_hash_a}" \
  | tee "${evidence_dir}/quicknotes-a.txt"

echo "== Runtime check =="
runtime_dir="${evidence_dir}/runtime"
mkdir -p "${runtime_dir}"
ADDR=127.0.0.1:18080 \
DATA_PATH="${runtime_dir}/notes.json" \
SEED_PATH="${repo_root}/app/seed.json" \
  "${quicknotes_store_a}/bin/quicknotes" >"${evidence_dir}/runtime.log" 2>&1 &
quicknotes_pid=$!
trap 'kill "${quicknotes_pid}" 2>/dev/null || true' EXIT
health_ok=0
for _ in $(seq 1 20); do
  if curl -fsS http://127.0.0.1:18080/health | tee "${evidence_dir}/health.json"; then
    health_ok=1
    break
  fi
  sleep 0.25
done
if [[ "${health_ok}" -ne 1 ]]; then
  echo "QuickNotes did not become healthy" >&2
  exit 1
fi
kill "${quicknotes_pid}"
wait "${quicknotes_pid}" || true
trap - EXIT

echo "== Docker image build A =="
nix build .#docker --print-build-logs
image_a="$(sha256sum result | awk '{print $1}')"
image_size="$(stat -Lc '%s' result)"
printf 'digest_a=%s\nsize_bytes=%s\n' "${image_a}" "${image_size}" \
  | tee "${evidence_dir}/image-a.txt"

echo "== Git/path source consistency check =="
nix build "path:${repo_root}#docker" --out-link result-path --print-build-logs
image_path_digest="$(sha256sum result-path | awk '{print $1}')"
printf 'git_digest=%s\npath_digest=%s\n' "${image_a}" "${image_path_digest}" \
  | tee "${evidence_dir}/source-consistency.txt"
if [[ "${image_a}" != "${image_path_digest}" ]]; then
  echo "Git and path flake inputs produced different image digests" >&2
  exit 1
fi

echo
echo "Environment A is complete. Run the environment-B commands from the report"
echo "in a fresh Nix container or on another machine; do not reuse this Nix store."
