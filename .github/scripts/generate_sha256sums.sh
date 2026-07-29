#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${1:?usage: generate_sha256sums.sh <dist-dir>}"
cd "$OUTPUT_DIR"
find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | sort | xargs -r sha256sum > SHA256SUMS
