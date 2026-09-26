import Foundation
import Security

// MARK: - Model

enum Proto: String, CaseIterable, Identifiable {
    case nfs, smb, webdav, s3

    var id: String { rawValue }
    var label: String {
        switch self {
        case .nfs: "NFS"
        case .smb: "SMB"
        case .webdav: "WebDAV"
        case .s3: "S3"
        }
    }
}

struct Share: Identifiable, Equatable {
    var name: String
    var proto: Proto = .nfs
    var server: String              // host, or host:port for SMB / WebDAV
    var path: String                // NFS "/export"  ·  SMB "share[/folder]"  ·  WebDAV "/dav" or ""
    var username = ""               // SMB / WebDAV, optional. Passwords live in the Keychain, never here.
    var https = true                // WebDAV only
    var options = ""                // NFS only; empty = mountiectl default (soft)
    var auto = false                // watch the server: mount when it appears, unmount when it goes away
    var viaTailscale = false        // ...counts as available while Tailscale is running
    var tailscaleAccounts: [String] = [] // ...restricted to these tailnets (empty = any account)
    var wifiNetworks: [String] = [] // ...or while connected to one of these Wi-Fi networks
    var mounted = false

    var id: String { name }
    var displayOptions: String { options.isEmpty ? "soft" : options }

    /// Whether the auto-mount conditions restrict when this share is considered available.
    var hasConditions: Bool { viaTailscale || !wifiNetworks.isEmpty }

    /// Whether the Tailscale condition is met. With accounts chosen, the active tailnet
    /// must be one of them; while running but unable to tell the account (no CLI, only
    /// the tunnel-interface fallback), a restricted share waits rather than risk the
    /// wrong tailnet.
    func tailscaleConditionMet(running: Bool, tailnet: String?) -> Bool {
        guard running else { return false }
        guard !tailscaleAccounts.isEmpty else { return true }
        guard let tailnet else { return false }
        return tailscaleAccounts.contains { $0.caseInsensitiveCompare(tailnet) == .orderedSame }
    }

    /// Why this auto share isn't eligible right now, or nil if it is. With conditions set,
    /// a share counts as available while the Tailscale condition is met OR the Mac is on
    /// one of the chosen Wi-Fi networks.
    func unavailableReason(tailscaleRunning: Bool, tailscaleTailnet: String?, ssid: String?) -> String? {
        guard hasConditions else { return nil }
        if viaTailscale && tailscaleConditionMet(running: tailscaleRunning, tailnet: tailscaleTailnet) { return nil }
        if let ssid, wifiNetworks.contains(ssid) { return nil }
        var wants: [String] = []
        if viaTailscale {
            wants.append(tailscaleAccounts.isEmpty ? "Tailscale" : "Tailscale (\(tailscaleAccounts.joined(separator: ", ")))")
        }
        if !wifiNetworks.isEmpty { wants.append("Wi-Fi (\(wifiNetworks.joined(separator: ", ")))") }
        return "Waiting for " + wants.joined(separator: " or ") + "…"
    }

    private func enc(_ s: String, _ allowed: CharacterSet) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// The share's address as written in shares.conf: always a URL (nfs://, smb://, http(s)://, s3://),
    /// percent-encoded so spaces etc. survive the whitespace-separated file.
    var spec: String {
        let user = username.isEmpty ? "" : enc(username, .urlUserAllowed) + "@"
        switch proto {
        case .nfs: return "nfs://\(server)\(enc(path, .urlPathAllowed))"
        case .smb: return "smb://\(user)\(server)/\(enc(path, .urlPathAllowed))"
        case .webdav: return "\(https ? "https" : "http")://\(user)\(server)\(enc(path, .urlPathAllowed))"
        case .s3: return "s3://\(server)/\(enc(path, .urlPathAllowed))"
        }
    }

    /// Human-readable address (no percent-encoding).
    var displaySpec: String {
        let user = username.isEmpty ? "" : username + "@"
        switch proto {
        case .nfs: return "nfs://\(server)\(path)"
        case .smb: return "smb://\(user)\(server)/\(path)"
        case .webdav: return "\(https ? "https" : "http")://\(user)\(server)\(path)"
        case .s3: return "s3://\(server)/\(path)"
        }
    }

    /// Parses the address column of shares.conf. Nil if it isn't valid.
    static func parse(name: String, spec: String, options: String) -> Share? {
        guard let c = URLComponents(string: spec), let host = c.host, !host.isEmpty else { return nil }
        let server = host + (c.port.map { ":\($0)" } ?? "")
        switch c.scheme?.lowercased() {
        case "nfs":
            guard c.path.hasPrefix("/") else { return nil }
            return Share(name: name, server: server, path: c.path, options: options)
        case "smb":
            let share = String(c.path.drop(while: { $0 == "/" }))
            guard !share.isEmpty else { return nil }            // a share name is required
            return Share(name: name, proto: .smb, server: server, path: share, username: c.user ?? "")
        case "http", "https":
            return Share(name: name, proto: .webdav, server: server, path: c.path,
                         username: c.user ?? "", https: c.scheme?.lowercased() == "https")
        case "s3":
            let bucket = String(c.path.drop(while: { $0 == "/" }))
            guard !bucket.isEmpty else { return nil }            // a bucket name is required
            return Share(name: name, proto: .s3, server: server, path: bucket)
        default:
            return nil
        }
    }
}

// MARK: - S3 credentials (Keychain)

/// S3 shares have no sign-in dialog to lean on, so Mountie keeps the access keys itself,
/// in the Keychain — never in shares.conf — and hands them to the bundled rclone
/// as `RCLONE_CONFIG_*` environment variables (rclone needs no config file).
enum S3Keys {
    struct Info: Codable, Equatable {
        var endpoint = ""     // host[:port]; empty = Amazon S3
        var region = ""       // optional
        var accessKey = ""
        var secret = ""
        var https = true      // scheme for custom endpoints, e.g. a LAN Minio over http
    }

    static let service = "wtf.laux.mountie.s3"

    /// The keys for a share, or nil if none are saved (or only partially).
    static func load(_ name: String) -> Info? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: name,
                                kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let info = try? JSONDecoder().decode(Info.self, from: data) else { return nil }
        return info.accessKey.isEmpty || info.secret.isEmpty ? nil : info
    }

    static func save(_ name: String, _ info: Info) {
        let data = try? JSONEncoder().encode(info)
        guard let data else { return }
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: name]
        let add = base.merging([kSecValueData as String: data]) { _, new in new }
        if SecItemAdd(add as CFDictionary, nil) == errSecDuplicateItem {
            SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        }
    }

    static func delete(_ name: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: name]
        SecItemDelete(q as CFDictionary)
    }

    /// Environment variables defining rclone's ephemeral `mountie` remote for this share.
    /// Nil when the keys are missing, so mounts and probes fail cleanly.
    static func env(for name: String) -> [String: String]? {
        guard let i = load(name) else { return nil }
        var e = ["RCLONE_CONFIG_MOUNTIE_TYPE": "s3",
                 "RCLONE_CONFIG_MOUNTIE_ACCESS_KEY_ID": i.accessKey,
                 "RCLONE_CONFIG_MOUNTIE_SECRET_ACCESS_KEY": i.secret]
        if i.endpoint.isEmpty {
            e["RCLONE_CONFIG_MOUNTIE_PROVIDER"] = "AWS"
        } else {
            e["RCLONE_CONFIG_MOUNTIE_PROVIDER"] = "Other"
            e["RCLONE_CONFIG_MOUNTIE_ENDPOINT"] = "\(i.https ? "https" : "http")://\(i.endpoint)"
        }
        if !i.region.isEmpty { e["RCLONE_CONFIG_MOUNTIE_REGION"] = i.region }
        return e
    }
}

// MARK: - Preferences (UserDefaults, domain wtf.laux.mountie)

enum Prefs {
    static let hideWindowOnLaunch = "hideWindowOnLaunch"
    static let unmountOnQuitKey = "unmountOnQuit"
    private static let autoKey = "autoMountShares"
    private static let tailscaleKey = "tailscaleShares"
    private static let sidebarKey = "sidebarShares"
    private static let wifiKey = "autoMountWifiNetworks"
    private static let tsAccountsKey = "autoMountTailscaleAccounts"
    private static let mountBaseKey = "mountBase"
    static let defaultMountBase = "~/Mountie"

    private static func names(_ key: String) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }
    private static func setNames(_ value: Set<String>, _ key: String) {
        UserDefaults.standard.set(value.sorted(), forKey: key)
    }

    /// Per-share auto-mount settings, keyed by share name.
    static var autoShares: Set<String> {
        get { names(autoKey) }
        set { setNames(newValue, autoKey) }
    }
    static var tailscaleShares: Set<String> {
        get { names(tailscaleKey) }
        set { setNames(newValue, tailscaleKey) }
    }
    /// Shares whose Finder sidebar entry Mountie itself added (removed again on unmount).
    static var sidebarShares: Set<String> {
        get { names(sidebarKey) }
        set { setNames(newValue, sidebarKey) }
    }
    static var wifiNetworks: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: wifiKey) as? [String: [String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: wifiKey) }
    }
    static var tailscaleAccounts: [String: [String]] {
        get { UserDefaults.standard.dictionary(forKey: tsAccountsKey) as? [String: [String]] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: tsAccountsKey) }
    }

    /// The folder shares are mounted in (one subfolder per share), as shown to the user, e.g. "~/Mountie".
    static var mountBase: String {
        get { UserDefaults.standard.string(forKey: mountBaseKey) ?? defaultMountBase }
        set {
            if newValue == defaultMountBase {
                UserDefaults.standard.removeObject(forKey: mountBaseKey)
            } else {
                UserDefaults.standard.set(newValue, forKey: mountBaseKey)
            }
        }
    }

    /// Whether quitting unmounts every mounted share. On by default — an unset value
    /// counts as on, so the preference reads true before the user ever touches it.
    static var unmountOnQuit: Bool {
        get { UserDefaults.standard.object(forKey: unmountOnQuitKey) == nil
              || UserDefaults.standard.bool(forKey: unmountOnQuitKey) }
        set { UserDefaults.standard.set(newValue, forKey: unmountOnQuitKey) }
    }

    /// The absolute shares folder. `MOUNTIE_BASE` in the environment overrides the preference (used by tests).
    static var mountBasePath: String {
        let raw = ProcessInfo.processInfo.environment["MOUNTIE_BASE"] ?? mountBase
        return (raw as NSString).expandingTildeInPath
    }

    /// nil if `input` can be used as the shares folder, otherwise what's wrong with it.
    static func problemWithMountBase(_ input: String) -> String? {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return "Choose a folder." }
        let path = (t as NSString).expandingTildeInPath
        guard path.hasPrefix("/") else { return "Use a full path, or one starting with ~." }
        let url = URL(fileURLWithPath: path).standardized
        guard url.path != "/" else { return "Choose a folder, not the whole disk." }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue { return "That path is a file, not a folder." }
            return fm.isWritableFile(atPath: url.path) ? nil : "Mountie can't write to that folder."
        }
        // Doesn't exist yet: the nearest existing parent must be writable so the folder can be created.
        var parent = url.deletingLastPathComponent()
        while !fm.fileExists(atPath: parent.path) && parent.path != "/" { parent.deleteLastPathComponent() }
        return fm.isWritableFile(atPath: parent.path) ? nil : "Mountie can't create that folder (no permission)."
    }

    /// Seconds between availability checks (`defaults write wtf.laux.mountie watchInterval 30` to change).
    static var watchInterval: Double {
        let v = UserDefaults.standard.double(forKey: "watchInterval")   // 0 when unset; also parses strings
        return v > 0 ? max(1, v) : 10
    }
}

// MARK: - Tailscale accounts

/// Tailscale profiles (accounts) set up on this Mac, relayed by mountiectl from the
/// Tailscale CLI (which owns the knowledge of where that CLI lives). Only one profile
/// is active at a time, and a share usually lives in one tailnet, so the auto-mount
/// condition can be restricted to specific accounts.
enum Tailscale {
    struct Account: Codable, Equatable, Identifiable {
        var id = ""
        var nickname = ""
        var tailnet = ""
        var account = ""
        var selected = false
    }

    /// Decodes the CLI's `switch --list --json` output; nil when it isn't that JSON.
    static func parseAccounts(_ json: String) -> [Account]? {
        try? JSONDecoder().decode([Account].self, from: Data(json.utf8))
    }

    /// The active tailnet as printed by `mountiectl tailscale`; nil when Tailscale isn't
    /// running, or is running but the account can't be told.
    static func parseTailnet(_ out: String) -> String? {
        let t = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// The profiles configured on this Mac, or nil when the CLI can't list them
    /// (not installed, or too old for `switch --list`) — callers fall back to "any account".
    static func accounts() async -> [Account]? {
        let r = await Ctl.run(["tailscale-accounts"])
        guard r.ok else { return nil }
        return parseAccounts(r.out)
    }
}

// MARK: - Config file + helper script

enum Ctl {
    struct Output { var ok: Bool; var out: String; var err: String }

    static var confURL: URL {
        if let p = ProcessInfo.processInfo.environment["MOUNTIE_CONF"] { return URL(fileURLWithPath: p) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mountie/shares.conf")
    }

    static var helperURL: URL {
        if let p = ProcessInfo.processInfo.environment["MOUNTIE_CTL"] { return URL(fileURLWithPath: p) }
        return URL(fileURLWithPath: (Bundle.main.resourcePath ?? "") + "/mountiectl")
    }

    /// One continuation with two racing finishers (the reader thread and the timeout timer):
    /// whoever gets here first resumes it, the other is a no-op.
    private final class Once<T>: @unchecked Sendable {   // the lock is the guarantee
        private let lock = NSLock()
        private var cont: CheckedContinuation<T, Never>?
        init(_ c: CheckedContinuation<T, Never>) { cont = c }
        func resume(_ value: T) {
            lock.lock(); let c = cont; cont = nil; lock.unlock()
            c?.resume(returning: value)
        }
    }

    /// Signals the helper and everything it spawned: Process starts it as the leader of its
    /// own process group, so the umount/diskutil it runs are in it too. If it somehow isn't a
    /// leader, signal the pid alone — never a group we could be part of ourselves.
    private static func signalGroup(_ pid: pid_t, _ sig: Int32) {
        guard pid > 0 else { return }
        if getpgid(pid) == pid { _ = killpg(pid, sig) } else { _ = kill(pid, sig) }
    }

    /// Runs the bundled mountiectl script off the main thread. `extraEnv` carries per-call
    /// variables (the S3 keys for rclone); it never persists anywhere.
    ///
    /// `timeout` is a hard cap: at the deadline the call returns ok=false right away — the
    /// caller must never wait on a helper that may not die (a umount wedged in the kernel on a
    /// vanished server) — and the helper's whole process group gets SIGTERM, then SIGKILL 2 s
    /// later if it's still there. Mounts must pass nil: s3_mount's disowned rclone shares the
    /// group and would die with it, and a mount may legitimately sit in a sign-in dialog.
    static func run(_ args: [String], extraEnv: [String: String]? = nil,
                    timeout: TimeInterval? = nil) async -> Output {
        var env = ProcessInfo.processInfo.environment
        env["MOUNTIE_BASE"] = Prefs.mountBasePath   // the script mounts into <shares folder>/<name>
        for (k, v) in extraEnv ?? [:] { env[k] = v }
        let environment = env
        return await withCheckedContinuation { (cont: CheckedContinuation<Output, Never>) in
            let once = Once(cont)
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = helperURL
                p.arguments = args
                p.environment = environment
                let o = Pipe(), e = Pipe()
                p.standardOutput = o
                p.standardError = e
                do { try p.run() } catch {
                    once.resume(Output(ok: false, out: "", err: error.localizedDescription))
                    return
                }
                var timer: DispatchSourceTimer?
                if let timeout {
                    let pid = p.processIdentifier
                    let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                    t.schedule(deadline: .now() + timeout)
                    t.setEventHandler {
                        // Report first, clean up second: the caller is free whatever the
                        // helper does from here on.
                        once.resume(Output(ok: false, out: "",
                            err: "Timed out after \(Int(timeout)) s (mountiectl \(args.joined(separator: " ")))"))
                        signalGroup(pid, SIGTERM)
                        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                            // Once Foundation has reaped it the pid may be recycled: don't signal then.
                            if p.isRunning { signalGroup(pid, SIGKILL) }
                        }
                    }
                    t.resume()
                    timer = t
                }
                // The pipes close when the script dies, even if a child it started outlives it
                // (its output goes to the script's own capture, not to us).
                let out = o.fileHandleForReading.readDataToEndOfFile()
                let err = e.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                timer?.cancel()
                once.resume(Output(
                    ok: p.terminationStatus == 0,
                    out: String(decoding: out, as: UTF8.self),
                    err: String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
    }

    /// `name address [options]` per line, `#` comments. Same rules as mountiectl.
    static func loadShares() -> [Share] {
        migrateOldConfig()
        guard let text = try? String(contentsOf: confURL, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.hasPrefix("#") { return nil }
            let f = t.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard f.count >= 2 else { return nil }
            return Share.parse(name: f[0], spec: f[1], options: f.dropFirst(2).joined(separator: " "))
        }
    }

    static func save(_ shares: [Share]) throws {
        var text = """
        # Shares managed by Mountie, one per line:
        #   name   address   [NFS mount options]
        # Addresses: nfs://host/export, smb://[user@]host/share, http(s)://[user@]host/path (WebDAV),
        #   s3://host/bucket (S3; host is the endpoint, empty means Amazon S3).
        # Each share mounts in its own subfolder of the shares folder (Preferences; default ~/Mountie).
        # Passwords are never stored here (SMB/WebDAV use the Keychain; S3 keys live in Mountie's Keychain).
        # Comments added by hand are not preserved when saving from the app.

        """
        for s in shares {
            text += "\(s.name)  \(s.spec)" + (s.proto == .nfs && !s.options.isEmpty ? "  \(s.options)" : "") + "\n"
        }
        try FileManager.default.createDirectory(
            at: confURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: confURL, atomically: true, encoding: .utf8)
    }

    /// One-time move of the pre-1.0 config (~/.config/mountie/shares.conf) to Application Support.
    private static func migrateOldConfig() {
        guard ProcessInfo.processInfo.environment["MOUNTIE_CONF"] == nil else { return }
        let fm = FileManager.default
        let old = fm.homeDirectoryForCurrentUser.appendingPathComponent(".config/mountie/shares.conf")
        guard fm.fileExists(atPath: old.path), !fm.fileExists(atPath: confURL.path) else { return }
        try? fm.createDirectory(at: confURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.moveItem(at: old, to: confURL)
    }
}
