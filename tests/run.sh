#!/bin/bash
# Runs every test suite. No phone, headphones or audio hardware required.
set -uo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
rc=0

./tests/test_pab.sh || rc=1

echo
echo "compiling swift logic tests…"
swiftc -target arm64-apple-macosx14.0 -o build/logic-tests \
       app/BridgeController.swift tests/main.swift || exit 1
./build/logic-tests || rc=1

echo
[ $rc -eq 0 ] && echo "all suites passed" || echo "FAILURES"
exit $rc
