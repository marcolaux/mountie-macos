Mountie 1.4.3 — a NAS that goes away no longer freezes the app, and Mountie tells you.

**Fixed in 1.4.3**
- **A share whose server went away froze Mountie.** Reads on a hard NFS mount wait for the server and can't be interrupted, so the app stopped responding and the menu bar item stopped working. All filesystem work on a share now happens outside the main thread, and Mountie never waits on a share it can't reach.
- **Every NFS mount gets `intr`**, in addition to your own options (`soft` by default). A call that is delayed on a server that stopped answering fails with `EINTR` when signalled, so it can be cut short instead of waiting for good.
- **Dead shares are marked, not hidden:** a share whose server stops answering is shown as **"not answering"** — in the window and in the menu bar — and the menu bar icon turns into a warning sign. Nothing is unmounted behind your back; the menu offers **Force Unmount** for it.
- **A mount that never finishes can be cancelled:** the menu bar entry of a share that is working on a hung mount offers **Cancel**.
- **The helper no longer deadlocks or strands a process:** its output is read concurrently, and a helper past its cap is stopped instead of left running.

**Install:** download the zip, unzip it, and drag Mountie to ~/Applications (or /Applications).
Notarized; macOS opens it without warnings. Existing installs update themselves.
