#!/bin/zsh
# Builds and runs the model tests. Usage: ./tests/run.sh
set -e
cd "${0:A:h}/.."
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
swiftc -swift-version 5 Model.swift tests/main.swift -o "$TMP/tests"
"$TMP/tests"

# mountiectl's `timed`: inside $(...) it must return when the command does (an orphaned
# guard sleep once held the capture pipe for the whole cap), and report 143 when the cap fires.
print "mountiectl timed"
/bin/zsh -c '
  zmodload zsh/datetime
  eval "$(sed -n "/^timed()/,/^}/p" mountiectl)"
  s=$EPOCHREALTIME; x=$(timed 5 sleep 1 2>&1)
  (( EPOCHREALTIME - s < 3 )) && print "  ok   returns when the command does" \
    || { print "  FAIL an orphaned guard holds the capture pipe"; exit 1 }
  x=$(timed 1 sleep 5 2>&1); rc=$?
  (( rc == 143 )) && print "  ok   reports 143 when the cap fires" \
    || { print "  FAIL cap did not fire (rc=$rc)"; exit 1 }'
