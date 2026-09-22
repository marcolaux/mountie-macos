Mountie 1.3.1 — fixes Location access and WebDAV sign-in on 1.3.0.

**Fixed in 1.3.1**
- **Location access:** 1.3.0 never asked for Location access, so automatic mounting by Wi-Fi network only worked after allowing Mountie manually in System Settings. Mountie now asks for it when it needs it. If you already allowed it in System Settings, nothing changes.
- **WebDAV and SMB sign-in:** when macOS already had a saved password for a server that no longer worked, mounting failed with "Authentication failed" and no sign-in dialog. Mountie now shows the sign-in dialog in that case. Automatic mounts still never show a dialog.

**Install:** download the zip, unzip it, and drag Mountie to ~/Applications (or /Applications).
Notarized; macOS opens it without warnings. Existing installs update themselves.
