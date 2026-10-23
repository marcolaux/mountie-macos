#!/bin/zsh
# PreToolUse hook for Bash: refuses commands that can delete data recursively or mount a
# network share. Reason: docs/incident-2026-10-23.md (an rm -rf crossed a live NFS mount).
# Exit 2 blocks the call and hands the message to the agent. The block is the answer —
# never rephrase a command to get past it.
set -u
cmd=$(/usr/bin/jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -z $cmd ]] && exit 0

deny() { print -u2 -- "BLOCKED by .claude/hooks/guard-bash.sh — $1. See docs/incident-2026-10-23.md. Use mv into .trash/ and ask the user."; exit 2 }

# Recursive deletes, however spelled: rm -r / -R / -rf / -fr / -r -f / --recursive, through
# sudo, /bin/rm, command, env, xargs, or find -exec.
if [[ $cmd =~ '(^|[^[:alnum:]_.-])rm([[:space:]]+[^[:space:]]+)*[[:space:]]+(-[[:alnum:]]*[rR][[:alnum:]]*|--recursive)([[:space:]]|$)' ]]; then
  deny "recursive rm"
fi
[[ $cmd =~ '(^|[^[:alnum:]_])find[[:space:]].*[[:space:]]-delete([[:space:]]|$)' ]] && deny "find -delete"
[[ $cmd =~ '(^|[^[:alnum:]_])find[[:space:]].*-exec(dir)?[[:space:]]+(sudo[[:space:]]+)?([^[:space:]]*/)?rm([[:space:]]|$)' ]] && deny "find -exec rm"
[[ $cmd =~ '(^|[^[:alnum:]_])git[[:space:]]+clean([[:space:]]|$)' ]] && deny "git clean (it removes untracked dirs, mounts included)"
[[ $cmd =~ '(^|[^[:alnum:]_])rsync[[:space:]].*--(delete|remove-source-files)' ]] && deny "rsync --delete"
[[ $cmd =~ 'shutil\.rmtree|FileManager[^;]*removeItem|(^|[^[:alnum:]_])rmtree\(' ]] && deny "recursive delete via a script"
[[ $cmd =~ '(^|[^[:alnum:]_])rclone[[:space:]]+(purge|delete|deletefile|rmdirs|sync|move|moveto|cleanup)([[:space:]]|$)' ]] && deny "destructive rclone command"
[[ $cmd =~ '(^|[^[:alnum:]_])diskutil[[:space:]]+(erase[[:alpha:]]*|partitionDisk|reformat|secureErase|zeroDisk|randomDisk|apfs[[:space:]]+delete)' ]] && deny "diskutil erase"
[[ $cmd =~ '(^|[^[:alnum:]_])(newfs_[[:alnum:]]+|mkfs[.[:alnum:]]*)([[:space:]]|$)' ]] && deny "filesystem format"

# Network mounts: the helper and every mount command it wraps.
[[ $cmd =~ '(^|[^[:alnum:]_])(mountiectl|netfsmount|mount_nfs|mount_smbfs|mount_ftp|mount_webdav|mount_afp|mount_9p)([[:space:]]|$)' ]] && deny "network mount command"
[[ $cmd =~ '(^|[^[:alnum:]_])mount[[:space:]]+(-[[:alnum:]]+[[:space:]]+)*-t([[:space:]]|$)' ]] && deny "mount -t"
[[ $cmd =~ '(^|[^[:alnum:]_])mount[[:space:]]+(-[[:alnum:]]+([[:space:]]+[^[:space:]]+)?[[:space:]]+)*[^[:space:]]+:/' ]] && deny "mount host:/export"
exit 0
