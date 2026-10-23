Mountie 1.4.1 — a quieter neighbor: Mountie now listens instead of checking.

**Changed in 1.4.1**
- **Far fewer background processes:** Mountie used to launch a status check every 5 seconds — several helper processes at a time, more with every share configured. It now listens to the system's own volume notifications and only checks when a share is actually mounted or ejected. A once-a-minute safety pass catches anything the notifications miss.
- **Instant reactions:** eject a share in Finder (or mount it from the terminal) and the menu bar updates within a second, instead of up to five.
- **Unrelated volumes cost nothing:** plugging in a USB stick or disk image no longer triggers a check.

**Install:** download the zip, unzip it, and drag Mountie to ~/Applications (or /Applications).
Notarized; macOS opens it without warnings. Existing installs update themselves.