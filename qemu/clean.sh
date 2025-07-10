#!/usr/bin/env bash
set -o pipefail

cd "$(dirname "$0")"

rm *.img || true
rm *.iso || true
rm *.log || true