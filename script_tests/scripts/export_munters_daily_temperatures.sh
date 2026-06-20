#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$ROOT_DIR"
exec dart --packages=backend/.dart_tool/package_config.json \
  scripts/export_munters_daily_temperatures.dart "$@"
