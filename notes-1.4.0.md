Mountie 1.4.0 — a share that won't unmount can't freeze the app anymore.

**Fixed in 1.4.0**
- **Busy shares no longer hang Mountie:** unmounting a share with files open in another app, or one whose server stopped answering, used to leave the app unresponsive until Force Quit. Every unmount is now capped at 20 seconds and always comes back to you.
- **Unmount dialog:** when a share won't go, Mountie asks — **Try Again** (after closing the files holding it), **Force Unmount**, or **Cancel**, and says why it failed ("still in use", "server isn't answering").
- **Quitting shows progress and can be cancelled:** an "Unmounting shares…" dialog with **Cancel** appears if the unmount takes more than a moment; the stuck-shares dialog then offers Try Again, Force Unmount, Keep Mounted, or Cancel. Logging out or shutting down never waits on a dialog.
- **No stray helper processes:** a timed-out unmount also stops the `umount` or `diskutil` it started.
- **Automatic mounting keeps going:** a server that vanished can no longer stall the watcher for good.

**Install:** download the zip, unzip it, and drag Mountie to ~/Applications (or /Applications).
Notarized; macOS opens it without warnings. Existing installs update themselves.
