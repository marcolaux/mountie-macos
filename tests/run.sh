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

# mountiectl's `list`: one mount-table read for the whole listing, tab-separated output
# the Swift parser depends on, and the same literal " on MP (" match as is_mounted.
print "mountiectl list"
/bin/zsh -c '
  dir=$(mktemp -d)
  print "one\tnfs://nas1.example/export\nother\tsmb://nas2.example/Documents" > "$dir/conf"
  cat > "$dir/fakemount" <<EOF
#!/bin/zsh
print x >> "$dir/calls"
print "nas1.example:/export on $dir/base/one (nfs, nobrowse)"
print "//nas2.example/Documents on /Volumes/elsewhere (smbfs)"
EOF
  chmod +x "$dir/fakemount"
  out=$(MOUNTIE_CONF="$dir/conf" MOUNTIE_BASE="$dir/base" MOUNTIE_MOUNT="$dir/fakemount" ./mountiectl list)
  [[ $out == $'"'"'one\tmounted\tnfs://nas1.example/export\nother\tunmounted\tsmb://nas2.example/Documents'"'"' ]] \
    && print "  ok   mounted and unmounted lines come out tab-separated, byte for byte" \
    || { print "  FAIL wrong listing: $out"; exit 1 }
  [[ $(wc -l < "$dir/calls") -eq 1 ]] \
    && print "  ok   the mount table is read once per listing" \
    || { print "  FAIL mount table read $(wc -l < "$dir/calls") times"; exit 1 }
  rm -rf "$dir"'
