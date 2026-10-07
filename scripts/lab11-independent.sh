#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
evidence_dir="${repo_root}/.goenv/lab11"
mkdir -p "${evidence_dir}"
cd "${repo_root}"

echo "== Environment B: fresh Nix store in a disposable container =="
docker run --rm \
  --entrypoint sh \
  -e 'NIX_CONFIG=experimental-features = nix-command flakes' \
  -v "${repo_root}:/work:ro" \
  -w /work \
  nixos/nix:2.31.2 \
  -eu -c '
    quicknotes_path="$(nix build path:/work#quicknotes --no-link --print-out-paths --print-build-logs)"
    printf "quicknotes_store_b=%s\n" "${quicknotes_path}"
    printf "quicknotes_hash_b=%s\n" "$(nix-store --query --hash "${quicknotes_path}")"
    image_path="$(nix build path:/work#docker --no-link --print-out-paths --print-build-logs)"
    printf "image_store_b=%s\n" "${image_path}"
    sha256sum "${image_path}"
  ' 2>&1 | tee "${evidence_dir}/environment-b.txt"

if [[ "${1:-all}" == "nix-only" ]]; then
  echo "Environment B Nix evidence captured; Docker comparison was skipped."
  exit 0
fi

echo "== Conventional Docker builds =="
docker build --no-cache -t qn-lab6:run1 ./app
docker build --no-cache -t qn-lab6:run2 ./app
{
  docker image inspect qn-lab6:run1 \
    --format 'run1 id={{.Id}} size={{.Size}} created={{.Created}}'
  docker image inspect qn-lab6:run2 \
    --format 'run2 id={{.Id}} size={{.Size}} created={{.Created}}'
} | tee "${evidence_dir}/docker-comparison.txt"

echo "== Nix image load and nonroot runtime proof =="
nix build .#docker --print-build-logs
docker load -i result | tee "${evidence_dir}/docker-load.txt"
docker rm -f quicknotes-lab11-nix >/dev/null 2>&1 || true
docker run --rm -d \
  --name quicknotes-lab11-nix \
  -p 127.0.0.1:18081:8080 \
  quicknotes:nix >/dev/null
trap 'docker rm -f quicknotes-lab11-nix >/dev/null 2>&1 || true' EXIT
health_ok=0
for _ in $(seq 1 20); do
  if curl -fsS http://127.0.0.1:18081/health \
    | tee "${evidence_dir}/container-health.json"; then
    health_ok=1
    break
  fi
  sleep 0.25
done
if [[ "${health_ok}" -ne 1 ]]; then
  echo "Nix-built container did not become healthy" >&2
  exit 1
fi
echo
docker image inspect quicknotes:nix \
  --format 'user={{.Config.User}} entrypoint={{json .Config.Entrypoint}} ports={{json .Config.ExposedPorts}}' \
  | tee "${evidence_dir}/nix-image-config.txt"
docker rm -f quicknotes-lab11-nix >/dev/null
trap - EXIT
