Mountie 1.3.0 — notarized, self-updating, and restart-proof.

**New in 1.3.0**
- **Notarized:** macOS opens Mountie without the unsigned-app warning. (The ticket is stapled, so it also verifies offline.)
- **Automatic updates:** Mountie now checks about once a day in the background and shows the new version with its notes (menu → Check for Updates…). It installs on your approval.
- **Restart-safe automatic mounting:** when a server answers its port but its shares aren't ready yet — a NAS rebooting, for instance — Mountie used to throw I/O errors and give up until the server disappeared and came back. It now checks that the share will actually mount (asking the NFS server for its export list, waiting for an HTTP response from WebDAV) without mounting anything, waits through the window, and retries periodically instead of giving up.

**Install:** download the zip, unzip it, and drag Mountie to ~/Applications (or /Applications).
Notarized; macOS opens it without warnings. Existing installs update themselves from 1.3.0 onward.