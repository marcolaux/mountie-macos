import Foundation
import NetFS

// Mounts an smb:// or http(s):// (WebDAV) URL at a directory using NetFS, the framework Finder
// uses, so passwords come from (and can be saved to) the user's Keychain and never appear on a
// command line or in a config file.
//
// Usage: netfsmount URL MOUNTPOINT [--quiet]     (--quiet: never show a sign-in dialog)

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let args = CommandLine.arguments
guard args.count >= 3, let url = URL(string: args[1]) else { fail("usage: netfsmount URL MOUNTPOINT [--quiet]", code: 2) }
let quiet = args.contains("--quiet")

// Key/value strings from NetFS.h (the CFSTR macros aren't imported into Swift).
func mount(ui: String) -> Int32 {
    let openOptions = NSMutableDictionary(dictionary: ["UIOption": ui])
    // MountAtMountDir: mount exactly at the given directory. MountFlags: MNT_DONTBROWSE (from
    // sys/mount.h) keeps the volume out of Finder's Locations/Desktop — Finder's sidebar shows
    // the share once, as the folder Mountie put there, not again under its server-derived name.
    let mountOptions = NSMutableDictionary(dictionary: ["MountAtMountDir": true,
                                                         "MountFlags": 0x00100000])
    var mountpoints: Unmanaged<CFArray>?
    return NetFSMountURLSync(url as CFURL, URL(fileURLWithPath: args[2]) as CFURL, nil, nil,
                             openOptions as CFMutableDictionary, mountOptions as CFMutableDictionary, &mountpoints)
}

var rc = mount(ui: quiet ? "NoUI" : "AllowUI")
// AllowUI only asks when macOS has no credentials of its own: a saved Keychain password that
// no longer works fails straight away, without a dialog. ForceUI always shows the sign-in.
if !quiet && rc == EAUTH {
    rc = mount(ui: "ForceUI")
}
if rc == 0 {
    print("Mounted")
    exit(0)
}

// Every message carries the code: EAUTH is the only one that means user name or password
// (NetFS returns it for a 401 as well as for a missing password). EACCES/EPERM come from
// the server refusing this user, or from macOS refusing the mount itself (a privacy block),
// and are not worth a sign-in dialog.
switch rc {
case EAUTH:
    fail(quiet
         ? "Sign-in required. Mount it once from the app so macOS can save the password to your Keychain."
         : "Authentication failed (error \(rc)).")
case EPERM:
    // What macOS returns when Mountie lacks Network Volumes access (Files & Folders), which
    // the mount needs; the prompt for it doesn't always appear (managed Macs suppress it).
    fail("macOS didn't allow the mount (error \(rc): \(String(cString: strerror(rc)))). In System Settings → "
         + "Privacy & Security, allow Mountie under Files & Folders → Network Volumes, or give it Full Disk Access.")
case EACCES:
    fail("Access denied (error \(rc): \(String(cString: strerror(rc)))). The server refused this user, "
         + "or macOS didn't allow the mount; check Mountie's access to Network Volumes in System Settings.")
case EEXIST:
    fail("This share is already mounted somewhere else (for example from Finder). Unmount it there first.")
case ECANCELED, -128:
    fail("Cancelled.")
case ENOENT, ENOTDIR:
    fail("The share or path wasn't found on the server.")
case -50:   // paramErr
    fail("The address isn't valid.")
case let code where code > 0:
    fail("\(String(cString: strerror(code))) (error \(code)).")
default:
    fail("NetFS error \(rc)")
}
