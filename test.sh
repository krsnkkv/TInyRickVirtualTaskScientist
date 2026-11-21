#!/bin/zsh
# Runs the unit checks in Tests/ against the app's logic files.
set -e
cd "$(dirname "$0")"
OUT=$(mktemp -d)
swiftc -swift-version 5 $(ls Sources/*.swift | grep -v "/main.swift") Tests/main.swift -o "$OUT/tests" 2>&1 | grep -E "error" || true
RICK_DATA_DIR="$OUT/data" RICK_PROFILES_DIR="$PWD/Profiles" "$OUT/tests"
