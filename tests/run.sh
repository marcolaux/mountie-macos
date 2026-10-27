#!/bin/zsh
# Builds and runs the model tests. Usage: ./tests/run.sh
set -e
cd "${0:A:h}/.."
# The scratch dir is moved into the repo's .trash/ when the run is over, not deleted:
# this project deletes nothing (see CLAUDE.md), and the OS clears /tmp anyway.
TMP=$(mktemp -d); trap 'mkdir -p .trash; mv "$TMP" .trash/tests-$$ 2>/dev/null' EXIT
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
  mkdir -p .trash; mv "$dir" .trash/list-test-$$ 2>/dev/null'

# mountiectl's `check`: how a mounted share is doing. The verdict is about the server, not
# just the mount table — a share whose server went away stays mounted, and that is exactly
# the case the app has to notice. The fake share points at 127.0.0.1: a local, fake server.
print "mountiectl check"
print "nas\tnfs://127.0.0.1/export\nweb\thttps://127.0.0.1/dav" > "$TMP/check.conf"
print "nas\tnfs://127.0.0.1/export\tvers=4" > "$TMP/opts.conf"
cat > "$TMP/fakemount" <<EOF
#!/bin/zsh
print "127.0.0.1:/export on $TMP/base/nas (nfs, nobrowse)"
EOF
chmod +x "$TMP/fakemount"
out=$(MOUNTIE_CONF="$TMP/check.conf" MOUNTIE_BASE="$TMP/base" MOUNTIE_MOUNT="$TMP/fakemount" ./mountiectl check nas 2>/dev/null) && rc=0 || rc=$?
[[ $rc == 2 && $out == unresponsive* ]] \
  && print "  ok   a mounted share whose server doesn't answer is unresponsive" \
  || { print "  FAIL wrong verdict: rc=$rc out=$out"; exit 1 }
out=$(MOUNTIE_CONF="$TMP/check.conf" MOUNTIE_BASE="$TMP/base" MOUNTIE_MOUNT="$TMP/fakemount" ./mountiectl check web 2>/dev/null) && rc=0 || rc=$?
[[ $rc == 1 && $out == unmounted* ]] \
  && print "  ok   a share that isn't mounted says so" \
  || { print "  FAIL wrong verdict: rc=$rc out=$out"; exit 1 }

# The other half of the verdict: the server answers, but the filesystem doesn't. A local
# listener stands in for the server; the mount point it points at doesn't exist.
python3 -I -m http.server 39411 --bind 127.0.0.1 >/dev/null 2>&1 & listener=$!
sleep 1
print "stale\tnfs://127.0.0.1:39411/export" > "$TMP/stale.conf"
cat > "$TMP/fakemount2" <<EOF
#!/bin/zsh
print "127.0.0.1:/export on $TMP/base/stale (nfs, nobrowse)"
EOF
chmod +x "$TMP/fakemount2"
out=$(MOUNTIE_CONF="$TMP/stale.conf" MOUNTIE_BASE="$TMP/base" MOUNTIE_MOUNT="$TMP/fakemount2" ./mountiectl check stale 2>/dev/null) && rc=0 || rc=$?
kill $listener 2>/dev/null
[[ $rc == 2 && $out == "unresponsive"* && $out == *"filesystem"* ]] \
  && print "  ok   a server that answers but a filesystem that doesn't is unresponsive" \
  || { print "  FAIL wrong verdict: rc=$rc out=$out"; exit 1 }

# And the healthy case: a server that answers and a filesystem that answers is simply
# mounted. The mount point has to exist for that — a share that is mounted has a folder.
mkdir -p "$TMP/base/healthy"
python3 -I -m http.server 39412 --bind 127.0.0.1 >/dev/null 2>&1 & listener=$!
sleep 1
print "healthy\tnfs://127.0.0.1:39412/export" > "$TMP/healthy.conf"
cat > "$TMP/fakemount3" <<EOF
#!/bin/zsh
print "127.0.0.1:/export on $TMP/base/healthy (nfs, nobrowse)"
EOF
chmod +x "$TMP/fakemount3"
out=$(MOUNTIE_CONF="$TMP/healthy.conf" MOUNTIE_BASE="$TMP/base" MOUNTIE_MOUNT="$TMP/fakemount3" ./mountiectl check healthy 2>/dev/null) && rc=0 || rc=$?
kill $listener 2>/dev/null
[[ $rc == 0 && $out == "mounted"* ]] \
  && print "  ok   a share that answers is mounted" \
  || { print "  FAIL wrong verdict: rc=$rc out=$out"; exit 1 }

# mountiectl's `opts`: the options a share is actually mounted with. Every NFS mount gets
# "intr", so a call delayed on a server that stopped answering can be cut short.
print "mountiectl opts"
out=$(MOUNTIE_CONF="$TMP/check.conf" MOUNTIE_BASE="$TMP/base" ./mountiectl opts nas)
[[ $out == "soft,intr" ]] \
  && print "  ok   the default is soft, and interruptible" \
  || { print "  FAIL wrong options: $out"; exit 1 }
out=$(MOUNTIE_CONF="$TMP/opts.conf" MOUNTIE_BASE="$TMP/base" ./mountiectl opts nas)
[[ $out == "vers=4,intr" ]] \
  && print "  ok   the share's own options are kept, and get intr" \
  || { print "  FAIL wrong options: $out"; exit 1 }
