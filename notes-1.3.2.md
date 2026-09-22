Mountie 1.3.2 — clearer errors when an SMB or WebDAV share doesn't mount.

**Fixed in 1.3.2**
- **Clearer mount errors:** Mountie used to report "Authentication failed" for any refused mount, even when the password wasn't the problem. Now only a real sign-in problem says so, and only then does Mountie show the sign-in dialog. Any other refusal says "Access denied", and it means either the server refused this user or macOS blocked the mount (for example, because Mountie isn't allowed to use the shares folder). Every error now includes its error code.

**Install:** download the zip, unzip it, and drag Mountie to ~/Applications (or /Applications).
Notarized; macOS opens it without warnings. Existing installs update themselves.
