Mountie 1.3.3 — asks for Local Network and folder access, so shares mount again.

**Fixed in 1.3.3**
- **Local Network access:** on some Macs, SMB and WebDAV shares on the local network failed with "Access denied (error 1: Operation not permitted)". macOS never asked for permission, and Mountie didn't appear in System Settings, so there was nothing to allow. Mountie now asks for Local Network access the first time it mounts a share on your network. If access is off, the message tells you where to turn it on.
- **Shares folder access:** if your shares folder is in a protected place (such as Documents, Desktop or iCloud Drive), Mountie now asks macOS for access before mounting. If access is off, the message tells you where to turn it on.

**Install:** download the zip, unzip it, and drag Mountie to ~/Applications (or /Applications).
Notarized; macOS opens it without warnings. Existing installs update themselves.
