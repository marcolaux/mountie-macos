#!/bin/zsh
# Builds and runs the model tests. Usage: ./tests/run.sh
set -e
cd "${0:A:h}/.."
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
swiftc -swift-version 5 Model.swift tests/main.swift -o "$TMP/tests"
"$TMP/tests"
