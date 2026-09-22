import Foundation

// Round-trip tests for the share model and shares.conf handling.
// Run: ./tests/run.sh
var failures = 0
func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if ok { print("  ok   \(what)") } else { print("  FAIL \(what) (line \(line))"); failures += 1 }
}

print("parse")
let nfs = Share.parse(name: "media", spec: "nfs://nas.example.com/volume1/media", options: "ro,soft")
check(nfs?.proto == .nfs && nfs?.server == "nas.example.com" && nfs?.path == "/volume1/media" && nfs?.options == "ro,soft", "NFS address")
check(nfs?.spec == "nfs://nas.example.com/volume1/media", "NFS spec is a URL")
let nfsSpaces = Share.parse(name: "a", spec: "nfs://10.0.0.5/srv/My%20Export", options: "")
check(nfsSpaces?.path == "/srv/My Export", "NFS path with an encoded space")
let smb = Share.parse(name: "nas", spec: "smb://alex%40corp@nas.example.com/Time%20Machine/Backups", options: "")
check(smb?.proto == .smb && smb?.username == "alex@corp" && smb?.server == "nas.example.com" && smb?.path == "Time Machine/Backups", "SMB with encoded user and spaces")
let dav = Share.parse(name: "cloud", spec: "https://dav.example.com:8443/remote.php/dav", options: "")
check(dav?.proto == .webdav && dav?.https == true && dav?.server == "dav.example.com:8443" && dav?.path == "/remote.php/dav", "WebDAV https with port and path")
check(Share.parse(name: "c", spec: "http://host", options: "")?.https == false, "WebDAV http, empty path")
check(Share.parse(name: "x", spec: "nas.example.com:/volume1/media", options: "") == nil, "the old host:/path syntax is no longer accepted")
check(Share.parse(name: "x", spec: "nfs://host", options: "") == nil, "NFS without an export path is rejected")
check(Share.parse(name: "x", spec: "smb://host", options: "") == nil, "SMB without a share is rejected")
check(Share.parse(name: "x", spec: "smb://host/", options: "") == nil, "SMB with empty share is rejected")
check(Share.parse(name: "x", spec: "ftp://host/x", options: "") == nil, "unknown scheme is rejected")
check(Share.parse(name: "x", spec: "nonsense", options: "") == nil, "garbage is rejected")
let s3 = Share.parse(name: "photos", spec: "s3://s3.us-east-1.amazonaws.com/my-bucket/photos", options: "")
check(s3?.proto == .s3 && s3?.server == "s3.us-east-1.amazonaws.com" && s3?.path == "my-bucket/photos", "S3 address with bucket and path")
let s3minio = Share.parse(name: "mn", spec: "s3://nas.example.com:9000/my%20bucket/sub", options: "")
check(s3minio?.server == "nas.example.com:9000" && s3minio?.path == "my bucket/sub", "S3 endpoint with port, encoded space")
check(Share.parse(name: "x", spec: "s3://host", options: "") == nil, "S3 without a bucket is rejected")
check(Share.parse(name: "x", spec: "s3://host/", options: "") == nil, "S3 with an empty bucket is rejected")

print("spec round trip")
let cases: [Share] = [
    Share(name: "a", server: "nas.example.com", path: "/volume1/media", options: "ro,soft"),
    Share(name: "b", server: "10.0.0.5", path: "/srv/My Export"),
    Share(name: "c", proto: .smb, server: "nas.example.com", path: "Time Machine/Backups", username: "alex@corp"),
    Share(name: "d", proto: .smb, server: "10.0.0.5:4455", path: "share"),
    Share(name: "e", proto: .webdav, server: "dav.example.com", path: "/a b/c", username: "me", https: true),
    Share(name: "f", proto: .webdav, server: "dav.example.com:8080", path: "", https: false),
    Share(name: "g", proto: .s3, server: "s3.us-east-1.amazonaws.com", path: "my-bucket/photos"),
    Share(name: "h", proto: .s3, server: "nas.example.com:9000", path: "my bucket/sub"),
]
for c in cases {
    let back = Share.parse(name: c.name, spec: c.spec, options: c.options)
    check(back == c, "\(c.proto.label) \(c.displaySpec)")
    check(!c.spec.contains(" "), "  spec has no spaces: \(c.spec)")
}

print("shares.conf save + load")
let tmp = NSTemporaryDirectory() + "mountie-test-\(getpid()).conf"
setenv("MOUNTIE_CONF", tmp, 1)
defer { try? FileManager.default.removeItem(atPath: tmp) }
try! Ctl.save(cases)
let text = try! String(contentsOfFile: tmp, encoding: .utf8)
check(Ctl.loadShares() == cases, "all protocols survive save then load")
check(!text.contains("password"), "no password field is ever written")
check(text.contains("a  nfs://nas.example.com/volume1/media  ro,soft"), "NFS line keeps its options")
check(!text.contains("smb://alex%40corp@nas.example.com/Time%20Machine/Backups  "), "SMB line has no options column")

print("hand-edited file")
try! """
# comment
old   nfs://nas/vol/old
web   https://dav.example.com/x
legacy nas:/vol/legacy
broken smb://onlyhost
bad-line
""".write(toFile: tmp, atomically: true, encoding: .utf8)
let loaded = Ctl.loadShares()
check(loaded.map(\.name) == ["old", "web"], "valid lines load; legacy and invalid ones are skipped")

print("shares folder")
let fm = FileManager.default
let sandbox = NSTemporaryDirectory() + "mountie-folder-\(getpid())"
try! fm.createDirectory(atPath: sandbox, withIntermediateDirectories: true)
defer { try? fm.removeItem(atPath: sandbox) }
fm.createFile(atPath: sandbox + "/a-file", contents: Data())
check(Prefs.problemWithMountBase("") != nil, "empty is rejected")
check(Prefs.problemWithMountBase("   ") != nil, "blank is rejected")
check(Prefs.problemWithMountBase("relative/path") != nil, "relative path is rejected")
check(Prefs.problemWithMountBase("/") != nil, "the whole disk is rejected")
check(Prefs.problemWithMountBase(sandbox + "/a-file") != nil, "a file is rejected")
check(Prefs.problemWithMountBase(sandbox) == nil, "an existing writable folder is fine")
check(Prefs.problemWithMountBase(sandbox + "/new/deeper/Shares") == nil, "a folder that can be created is fine")
check(Prefs.problemWithMountBase("  " + sandbox + "  ") == nil, "surrounding spaces are ignored")
check(Prefs.problemWithMountBase("/usr/nope/Shares") != nil, "a folder that can't be created is rejected")
check(Prefs.problemWithMountBase("~/Mountie") == nil, "~/Mountie is usable")

unsetenv("MOUNTIE_BASE")
Prefs.mountBase = Prefs.defaultMountBase
check(Prefs.mountBase == "~/Mountie", "default folder is ~/Mountie")
check(Prefs.mountBasePath == NSHomeDirectory() + "/Mountie", "the default expands to the home folder")
Prefs.mountBase = "~/Elsewhere/Shares"
check(Prefs.mountBase == "~/Elsewhere/Shares" && Prefs.mountBasePath == NSHomeDirectory() + "/Elsewhere/Shares", "a chosen folder is remembered")
setenv("MOUNTIE_BASE", "/tmp/from-env", 1)
check(Prefs.mountBasePath == "/tmp/from-env", "MOUNTIE_BASE overrides the preference")
unsetenv("MOUNTIE_BASE")
Prefs.mountBase = Prefs.defaultMountBase
check(UserDefaults.standard.string(forKey: "mountBase") == nil, "resetting removes the saved value")

print("sidebar preference")
check(Prefs.sidebarShares.isEmpty, "no shares recorded initially")
Prefs.sidebarShares = ["NAS", "Nextcloud"]
check(Prefs.sidebarShares == ["NAS", "Nextcloud"], "added sidebar entries are remembered")
Prefs.sidebarShares.remove("Nextcloud")
check(Prefs.sidebarShares == ["NAS"], "removing a share unrecords its sidebar entry")
Prefs.sidebarShares = []
check(UserDefaults.standard.stringArray(forKey: "sidebarShares") == nil ||
      UserDefaults.standard.stringArray(forKey: "sidebarShares")!.isEmpty, "clearing leaves no saved names")

print("unmount-on-quit preference")
Prefs.unmountOnQuit = false
check(!Prefs.unmountOnQuit, "turning it off is remembered")
Prefs.unmountOnQuit = true
check(Prefs.unmountOnQuit, "turning it on is remembered")
UserDefaults.standard.removeObject(forKey: Prefs.unmountOnQuitKey)
check(Prefs.unmountOnQuit, "an unset preference defaults to on")

print("tailscale condition")
var ts = Share(name: "media", server: "nas.example.com", path: "/vol")
ts.viaTailscale = true
check(ts.hasConditions, "the Tailscale condition counts as a condition")
check(ts.unavailableReason(tailscaleRunning: false, tailscaleTailnet: nil, ssid: nil) != nil, "Tailscale not running: share waits")
check(ts.unavailableReason(tailscaleRunning: true, tailscaleTailnet: nil, ssid: nil) == nil,
      "any account: running without a known tailnet is enough")
ts.tailscaleAccounts = ["example.com"]
check(ts.unavailableReason(tailscaleRunning: true, tailscaleTailnet: "example.com", ssid: nil) == nil,
      "the chosen tailnet is active")
check(ts.unavailableReason(tailscaleRunning: true, tailscaleTailnet: "alex@example.org", ssid: nil)
      == "Waiting for Tailscale (example.com)…", "another tailnet active: waits, and says which account")
check(ts.unavailableReason(tailscaleRunning: true, tailscaleTailnet: nil, ssid: nil) != nil,
      "unknown account: a restricted share waits")
check(ts.unavailableReason(tailscaleRunning: true, tailscaleTailnet: "EXAMPLE.com", ssid: nil) == nil,
      "the tailnet match ignores case")
ts.wifiNetworks = ["Home"]
check(ts.unavailableReason(tailscaleRunning: true, tailscaleTailnet: "alex@example.org", ssid: "Home") == nil,
      "Wi-Fi still rescues a wrong account (either is enough)")
ts.viaTailscale = false
ts.wifiNetworks = []
check(!ts.hasConditions, "accounts without the Tailscale condition are not a condition")
check(ts.unavailableReason(tailscaleRunning: false, tailscaleTailnet: nil, ssid: nil) == nil,
      "no conditions: available regardless")

print("tailscale account parsing")
let profiles = """
[
  {
    "id": "308a",
    "nickname": "Alex@example.com",
    "tailnet": "example.com",
    "account": "Alex@example.com",
    "selected": false
  },
  {
    "id": "9ade",
    "nickname": "alex@example.org",
    "tailnet": "alex@example.org",
    "account": "alex@example.org",
    "selected": true
  }
]
"""
let accounts = Tailscale.parseAccounts(profiles)
check(accounts?.count == 2, "both profiles decode")
check(accounts?[0].tailnet == "example.com" && accounts?[0].selected == false, "the work profile decodes")
check(accounts?[1].tailnet == "alex@example.org" && accounts?[1].selected == true, "the active profile is marked")
check(Tailscale.parseAccounts("ID  TAILNET  ACCOUNT") == nil, "a non-JSON table doesn't decode")
check(Tailscale.parseTailnet("alex@example.org\n") == "alex@example.org", "stdout is read as the tailnet")
check(Tailscale.parseTailnet("") == nil && Tailscale.parseTailnet(" \n") == nil, "blank stdout means the account is unknown")

print("tailscale account preference")
check(Prefs.tailscaleAccounts.isEmpty, "no accounts recorded initially")
Prefs.tailscaleAccounts = ["media": ["example.com"]]
check(Prefs.tailscaleAccounts["media"] == ["example.com"], "a share's chosen accounts are remembered")
Prefs.tailscaleAccounts["media"] = nil
check(Prefs.tailscaleAccounts.isEmpty, "clearing a share's accounts removes them")
UserDefaults.standard.removeObject(forKey: "autoMountTailscaleAccounts")

print(failures == 0 ? "\nall passed" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
