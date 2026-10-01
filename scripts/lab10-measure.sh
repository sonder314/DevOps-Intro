#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <space-base-url> <verify|warm|cold>" >&2
  exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVIDENCE_DIR="$ROOT_DIR/submissions/evidence/lab10"
BASE_URL="${1%/}"
MODE="$2"
HEALTH_URL="$BASE_URL/health"
CSV_FILE="$EVIDENCE_DIR/latency.csv"

mkdir -p "$EVIDENCE_DIR"
if [[ ! -f "$CSV_FILE" ]]; then
  printf 'timestamp,mode,sample,time_seconds\n' >"$CSV_FILE"
fi

measure() {
  curl --fail --silent --show-error --output /dev/null \
    --write-out '%{time_total}' "$HEALTH_URL"
}

case "$MODE" in
  verify)
    curl --fail --silent --show-error --verbose "$HEALTH_URL" \
      --output "$EVIDENCE_DIR/health-body.json" \
      2>"$EVIDENCE_DIR/health-curl-verbose.txt"
    echo "Saved the public health response and curl trace in $EVIDENCE_DIR"
    ;;
  warm)
    values=()
    for sample in {1..5}; do
      value="$(measure)"
      values+=("$value")
      printf '%s,warm,%d,%s\n' "$(date --iso-8601=seconds)" "$sample" "$value" \
        | tee -a "$CSV_FILE"
    done
    p50="$(printf '%s\n' "${values[@]}" | sort -n | sed -n '3p')"
    printf 'warm_samples=5\nwarm_p50_seconds=%s\n' "$p50" \
      | tee "$EVIDENCE_DIR/warm-summary.txt"
    ;;
  cold)
    value="$(measure)"
    sample="$(( $(awk -F, '$2 == "cold" {count++} END {print count+0}' "$CSV_FILE") + 1 ))"
    printf '%s,cold,%d,%s\n' "$(date --iso-8601=seconds)" "$sample" "$value" \
      | tee -a "$CSV_FILE"
    echo "Cold sample $sample recorded. Let the Space sleep for 35+ minutes before the next cold sample."
    ;;
  *)
    echo "Mode must be verify, warm, or cold" >&2
    exit 2
    ;;
esac
