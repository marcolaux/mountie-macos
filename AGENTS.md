# Mountie — agent instructions

macOS menu-bar app (SwiftUI, `LSUIElement`). Two-file build: `Model.swift` + `Mountie.swift`
compiled by `./build.sh` (ad-hoc, no Sparkle); `./build.sh release` adds `-DRELEASE` and the
Sparkle framework. Helper: zsh script `mountiectl` (env overrides `MOUNTIE_CONF`, `MOUNTIE_BASE`,
`MOUNTIE_STATE`, `MOUNTIE_CTL`, `MOUNTIE_MOUNT`). Tests: `./tests/run.sh`. Release = VERSION bump,
release notes, `./build.sh release`, commit.

## Data safety — NON-NEGOTIABLE

**Read `docs/incident-2026-10-23.md` before running anything in this repo.** On 2026-10-23 an
agent's cleanup `rm -rf` followed a live NFS mount and deleted ~2,800 files on the user's real
NAS. These rules exist so it can never happen again. No task justifies breaking them; if a rule
blocks the work, stop and ask the user instead of working around it.

1. **Never touch the user's real NAS or any real share.** Never mount it, never write to or
   delete from it, and never put a real share spec in a test config. Test confs use an
   `hdiutil` dmg (fake local share) only.
2. **No recursive deletes, ever.** `rm -rf` / `rm -r` / `rm -R` variants are denied at the
   permission level in `.claude/settings.json` — including via `sudo` — and the PreToolUse hook
   `.claude/hooks/guard-bash.sh` refuses every other spelling (`/bin/rm`, `find -delete`,
   `git clean`, `rsync --delete`, script-level rmtree) plus any network-mount command. Cleanup
   means `mv` into a repo-local `.trash/` dir; final deletion only with the user's explicit OK.
3. **Before deleting or moving any directory, check `/sbin/mount` for mounts beneath the
   target.** Mounts are invisible in `ls` and Finder; `rm` crosses them.
4. **Unmount and verify the mount table is clean** before removing any scratch dir that any
   Mountie instance (test or real) has touched.
5. The e2e recipe (dmg + env overrides + System Events) lives in Claude Code auto-memory:
   `e2e-busy-share-testing`.

If a permission system, sandbox, or safety check blocks a destructive action, **the block is
the answer** — never rephrase the command to get around it.