import SwiftUI
import ServiceManagement
import Network
import CoreWLAN
import CoreLocation
import CoreServices
import os
#if RELEASE
import Sparkle
#endif

// The share model, shares.conf handling and preferences live in Model.swift.

// MARK: - Wi-Fi

/// macOS only reveals the name of the network you're on to apps with Location access.
/// The list of remembered networks needs no permission.
@MainActor
final class LocationAccess: NSObject, CLLocationManagerDelegate, ObservableObject {
    static let shared = LocationAccess()

    private let manager = CLLocationManager()
    @Published private(set) var status: CLAuthorizationStatus = .notDetermined

    /// `MOUNTIE_LOCATION=notDetermined|denied` fakes the status (used by tests); requests are then
    /// logged and treated as "Allow" instead of reaching macOS.
    private static let simulated: CLAuthorizationStatus? = {
        switch ProcessInfo.processInfo.environment["MOUNTIE_LOCATION"] {
        case "notDetermined": .notDetermined
        case "denied": .denied
        default: nil
        }
    }()

    override init() {
        super.init()
        manager.delegate = self
        status = Self.simulated ?? manager.authorizationStatus
    }

    var isAuthorized: Bool { status == .authorizedAlways }

    func request() {
        if Self.simulated != nil {
            Logger(subsystem: "wtf.laux.mountie", category: "location").notice("requesting Location access")
            if status == .notDetermined { status = .authorizedAlways }
            Task { await Store.shared.watchTick() }
            return
        }
        NSApp.activate()
        manager.requestAlwaysAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let s = manager.authorizationStatus
        Task { @MainActor in
            guard Self.simulated == nil else { return }   // a faked status (tests) wins over macOS's
            self.status = s
            await Store.shared.watchTick()   // a Wi-Fi rule may have just become usable
        }
    }
}

@MainActor
enum WiFi {
    /// `MOUNTIE_SSID_FILE` substitutes a file's contents for the real network name (used by tests).
    private static var override: String? { ProcessInfo.processInfo.environment["MOUNTIE_SSID_FILE"] }

    /// Automatic mounting depends on Location access (macOS won't reveal the network name without it),
    /// so without it the whole feature is off. The test override counts as granted.
    static var locationGranted: Bool { override != nil || LocationAccess.shared.isAuthorized }

    /// Networks this Mac has joined before, sorted by name.
    /// `MOUNTIE_KNOWN_WIFI` (comma-separated) substitutes a fake list (used by tests).
    static func knownNetworks() -> [String] {
        if let list = ProcessInfo.processInfo.environment["MOUNTIE_KNOWN_WIFI"] {
            return list.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        let profiles = CWWiFiClient.shared().interface()?.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []
        return Set(profiles.compactMap(\.ssid)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The network we're connected to, or nil (not on Wi-Fi, or no Location access).
    static func currentSSID() -> String? {
        if let path = override {
            let s = (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (s?.isEmpty ?? true) ? nil : s
        }
        return CWWiFiClient.shared().interface()?.ssid()
    }
}

// MARK: - Finder sidebar

/// Puts a share's folder into Finder's Favorites while it's mounted, named after the share.
/// macOS offers no supported API for this; the deprecated-but-working LSSharedFileList
/// (the only mechanism, also used by tools like mysides) is the best there is. Everything
/// here is best-effort: failures are logged, never shown, and never affect mounting.
///
/// The API has been deprecated since 10.11 and Swift offers no per-use-site suppression,
/// so every LSSharedFileList symbol — functions and globals alike — is resolved through
/// dlsym and called as a raw C convention rather than through the Swift import: nothing
/// deprecated is referenced statically, so the build warns nowhere. (This enum was first
/// marked @available-deprecated to silence the API warnings inside it, which then warned
/// at its two callers; dlsym was already needed for the insert call, so it does it all.)
enum Sidebar {
    private static let log = Logger(subsystem: "wtf.laux.mountie", category: "sidebar")

    // MARK: deprecated-API bridge

    /// Resolves a symbol at runtime (RTLD_DEFAULT has no Swift name; -1 is its value).
    private static func sym<T>(_ name: String) -> T? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -1), name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }

    /// Reads a C global's pointer value — both constants we need are pointer storages
    /// (the Favorites list's CFStringRef, and the end-of-list sentinel item ref).
    private static func global(_ name: String) -> UnsafeRawPointer? {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: -1), name) else { return nil }
        return UnsafeRawPointer(p).load(as: UnsafeRawPointer.self)
    }

    /// kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes, from the
    /// header's anonymous C enum (not imported into Swift). The mount flag matters:
    /// resolving a stale entry must never spin up a network mount.
    private static let resolveFlags: UInt32 = (1 << 0) | (1 << 1)

    /// The C conventions, in the header's argument order, with CF objects crossing as the raw
    /// pointers the ABI passes and +1 returns as Unmanaged (so ARC releases them) — except
    /// where retain semantics are the problem, see InsertItem.
    private typealias CreateList = @convention(c) (
        UnsafeRawPointer?, UnsafeRawPointer, UnsafeRawPointer?
    ) -> Unmanaged<LSSharedFileList>?
    private typealias CopySnapshot = @convention(c) (
        UnsafeRawPointer, UnsafeMutablePointer<UInt32>?
    ) -> Unmanaged<CFArray>?
    /// LSSharedFileListInsertItemURL, called with a raw C convention: the end-of-list
    /// position (kLSSharedFileListItemLast) is a magic bit pattern, not a real item, and
    /// Swift's bridge would objc_retain it — and crash on it (found the hard way).
    private typealias InsertItem = @convention(c) (
        UnsafeRawPointer, UnsafeRawPointer, UnsafeRawPointer?, UnsafeRawPointer?,
        UnsafeRawPointer, UnsafeRawPointer?, UnsafeRawPointer?
    ) -> UnsafeMutableRawPointer?
    private typealias CopyResolvedURL = @convention(c) (
        UnsafeRawPointer, UInt32, UnsafeMutablePointer<UnsafeMutableRawPointer?>?
    ) -> Unmanaged<CFURL>?
    private typealias CopyDisplayName = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFString>?
    private typealias RemoveItem = @convention(c) (UnsafeRawPointer, UnsafeRawPointer) -> Int32
    /// CFRelease (Swift doesn't import it) — for the +1 reference the insert hands back.
    private typealias CFReleaseFn = @convention(c) (UnsafeRawPointer?) -> Void

    private static let fnCreate: CreateList? = sym("LSSharedFileListCreate")
    private static let fnSnapshot: CopySnapshot? = sym("LSSharedFileListCopySnapshot")
    private static let fnInsert: InsertItem? = sym("LSSharedFileListInsertItemURL")
    private static let fnResolvedURL: CopyResolvedURL? = sym("LSSharedFileListItemCopyResolvedURL")
    private static let fnDisplayName: CopyDisplayName? = sym("LSSharedFileListItemCopyDisplayName")
    private static let fnRemove: RemoveItem? = sym("LSSharedFileListItemRemove")
    private static let fnCFRelease: CFReleaseFn? = sym("CFRelease")

    /// kLSSharedFileListFavoriteItems — the Favorites list's type, held by the global.
    private static let favoritesType: UnsafeRawPointer? = global("kLSSharedFileListFavoriteItems")
    /// The end-of-list sentinel's bit pattern (reading the extern is safe; only the call
    /// bridge's retain of it isn't).
    private static let positionLast: UnsafeRawPointer? = global("kLSSharedFileListItemLast")

    /// The folder the share mounts in, as mountiectl computes it (MP="$BASE/$NAME").
    private static func url(for name: String) -> URL {
        URL(fileURLWithPath: Prefs.mountBasePath).appendingPathComponent(name)
    }

    private static func favorites() -> LSSharedFileList? {
        guard let fnCreate, let type = favoritesType else { log.warning("no favorites list"); return nil }
        return fnCreate(nil, type, nil)?.takeRetainedValue()
    }

    /// One pass over the list: the entry pointing at `url` (nil if none), plus every dead entry
    /// — its bookmark no longer resolves — named `name`. Paths are compared after resolving
    /// symlinks, since that's how Finder stores them (it turned /tmp/… into /private/tmp/…
    /// when this was learned). The snapshot is a CFArray of opaque items.
    ///
    /// Dead entries pile up for WebDAV: a bookmark to a WebDAV mount stops resolving once the
    /// volume is remounted, so the next add found no entry for the folder and inserted another
    /// one — the old ones lingered in Finder as duplicates under the share's name.
    private static func scan(_ list: LSSharedFileList, _ url: URL, _ name: String)
        -> (live: LSSharedFileListItem?, dead: [LSSharedFileListItem])? {
        guard let fnSnapshot, let fnResolvedURL, let fnDisplayName else {
            log.warning("snapshot unavailable"); return nil
        }
        let target = url.resolvingSymlinksInPath().path
        let rawList = unsafeBitCast(list, to: UnsafeRawPointer.self)
        guard let snapshot = fnSnapshot(rawList, nil)?.takeRetainedValue() else { return nil }
        var live: LSSharedFileListItem?, dead: [LSSharedFileListItem] = []
        for i in 0..<CFArrayGetCount(snapshot) {
            let item = unsafeBitCast(CFArrayGetValueAtIndex(snapshot, i), to: LSSharedFileListItem.self)
            let rawItem = unsafeBitCast(item, to: UnsafeRawPointer.self)
            if let found = fnResolvedURL(rawItem, resolveFlags, nil)?.takeRetainedValue() as URL? {
                if live == nil, found.resolvingSymlinksInPath().path == target { live = item }
            } else if fnDisplayName(rawItem)?.takeRetainedValue() as String? == name {
                dead.append(item)
            }
        }
        return (live, dead)
    }

    /// Adds the share's folder to Favorites under the share's name. False if the list already
    /// has an entry for the folder — insert would only *update* it (upsert), and an existing
    /// entry is the user's own favorite: never recorded, so never removed by Mountie.
    ///
    /// `owned`: Mountie added this share's entry before, so dead entries under its name are
    /// Mountie's leftovers and are cleared first (on every reconcile, which heals duplicates
    /// that were already there).
    static func add(_ name: String, owned: Bool) -> Bool {
        guard let list = favorites() else { return false }
        let url = url(for: name)
        guard let (live, dead) = scan(list, url, name) else { return false }
        if owned { for item in dead { _ = removeItem(list, item, name: name, path: url.path) } }
        if live != nil { return false }
        // The mounted folder sits on a network volume, and sharedfilelistd refuses to insert an
        // entry pointing at one unless the app holds the Files-and-Folders "Network Volumes"
        // permission. Its check fails silently, so this access triggers macOS's own one-time
        // prompt instead ("Mountie would like to access files on a network volume").
        _ = try? FileManager.default.contentsOfDirectory(atPath: url.path)
        guard let fnInsert, let positionLast else { log.warning("LSSharedFileListInsertItemURL unavailable"); return false }
        // The C call only sees raw pointers, so keep the bridged objects alive through it.
        let displayName = name as CFString, cfURL = url as CFURL
        let item = withExtendedLifetime((list, displayName, cfURL)) {
            fnInsert(unsafeBitCast(list, to: UnsafeRawPointer.self), positionLast,
                     unsafeBitCast(displayName, to: UnsafeRawPointer.self), nil,
                     unsafeBitCast(cfURL, to: UnsafeRawPointer.self), nil, nil)
        }
        guard let item else {
            log.warning("couldn't add \(url.path, privacy: .public) to the sidebar")
            return false
        }
        fnCFRelease?(item)   // we only wanted the insertion
        return true
    }

    /// Removes the entry pointing at the share's folder (only ever for entries Mountie added).
    /// True when the sidebar no longer holds an entry for the share — so still true when there
    /// never was one (already deleted by the user, nothing to clean up). False when a removal
    /// failed or the list can't be read, so the caller keeps its record and reconciles again.
    ///
    /// An entry whose folder is gone — unmount removes it, so a dead entry can linger between
    /// the unmount and this call — no longer resolves through its bookmark, so it's matched by
    /// the display name instead; all such entries go. A live favorite (one that resolves) is
    /// never matched by name.
    static func remove(_ name: String) -> Bool {
        guard let list = favorites() else { return false }
        let url = url(for: name)
        guard let (live, dead) = scan(list, url, name) else { return false }
        var ok = true
        for item in (live.map { [$0] } ?? []) + dead where !removeItem(list, item, name: name, path: url.path) {
            ok = false
        }
        return ok
    }

    private static func removeItem(_ list: LSSharedFileList, _ item: LSSharedFileListItem,
                                   name: String, path: String) -> Bool {
        guard let fnRemove else { log.warning("LSSharedFileListItemRemove unavailable"); return false }
        if fnRemove(unsafeBitCast(list, to: UnsafeRawPointer.self),
                    unsafeBitCast(item, to: UnsafeRawPointer.self)) != noErr {
            log.warning("couldn't remove \(path, privacy: .public) from the sidebar")
            return false
        }
        return true
    }
}

// MARK: - Mount preflight

/// macOS asks for Local Network access and for protected folders (Documents, Desktop, iCloud
/// Drive, other volumes) only when the app itself does the access. When the bundled helpers
/// do it, the answer can be a silent "Operation not permitted" instead of a prompt. So before
/// every mount the app touches the server and the mount folder itself, which makes macOS ask
/// Mountie — and turns a refusal into a message saying where to allow it.
enum Preflight {
    /// Why this share can't be mounted right now, or nil to go ahead.
    static func problem(for share: Share) async -> String? {
        if let p = folderProblem(for: share) { return p }
        return await networkProblem(for: share)
    }

    /// Creates the share's mount folder (mountiectl would too) and lists the shares folder.
    static func folderProblem(for share: Share) -> String? {
        let base = URL(fileURLWithPath: Prefs.mountBasePath)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: base.appendingPathComponent(share.name), withIntermediateDirectories: true)
            _ = try fm.contentsOfDirectory(atPath: base.path)
            return nil
        } catch {
            let shown = (base.path as NSString).abbreviatingWithTildeInPath
            return "macOS isn't letting Mountie use the shares folder \(shown). Allow Mountie in System Settings "
                + "→ Privacy & Security → Files & Folders (or Full Disk Access), or choose another shares folder "
                + "in Mountie's settings. (\(error.localizedDescription))"
        }
    }

    /// Connects to the server's port from the app. For a server on the local network this is
    /// what brings up macOS's Local Network prompt; while it's showing, this waits for the answer.
    /// Anything other than a Local Network refusal is left to mountiectl to report.
    static func networkProblem(for share: Share) async -> String? {
        guard let (host, port) = endpoint(of: share), let nwPort = NWEndpoint.Port(rawValue: port) else { return nil }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        // Only touched on `queue` (every handler below runs there), hence @unchecked.
        final class Probe: @unchecked Sendable {
            var done = false, waitingOnPrompt = false
            let cont: CheckedContinuation<Bool, Never>, conn: NWConnection
            init(_ cont: CheckedContinuation<Bool, Never>, _ conn: NWConnection) { self.cont = cont; self.conn = conn }
            func finish(_ denied: Bool) {
                guard !done else { return }
                done = true
                conn.cancel()
                cont.resume(returning: denied)
            }
        }
        let denied: Bool = await withCheckedContinuation { cont in
            let queue = DispatchQueue(label: "wtf.laux.mountie.preflight")
            let probe = Probe(cont, conn)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready, .failed, .cancelled: probe.finish(false)
                case .waiting:
                    if probe.conn.currentPath?.unsatisfiedReason == .localNetworkDenied {
                        probe.waitingOnPrompt = true   // prompt showing, or access denied: keep waiting a while
                    } else {
                        probe.finish(false)            // refused/unreachable: mountiectl says so in its own words
                    }
                default: break
                }
            }
            conn.start(queue: queue)
            // A plain connection settles within seconds; one blocked by Local Network gets time
            // for the user to answer the prompt, then counts as denied.
            queue.asyncAfter(deadline: .now() + 5) { if !probe.waitingOnPrompt { probe.finish(false) } }
            queue.asyncAfter(deadline: .now() + 60) { probe.finish(probe.waitingOnPrompt) }
        }
        guard denied else { return nil }
        return "macOS isn't letting Mountie reach \(host) on your local network. Allow Mountie in System Settings "
            + "→ Privacy & Security → Local Network, then mount again."
    }

    /// Host and port the share's mount connects to (same defaults as mountiectl), nil for Amazon S3.
    static func endpoint(of share: Share) -> (String, UInt16)? {
        var host = share.server, port: UInt16?
        if host.hasPrefix("["), let close = host.firstIndex(of: "]") {             // [IPv6]:port
            port = UInt16(host[host.index(after: close)...].dropFirst())
            host = String(host[host.index(after: host.startIndex)..<close])
        } else if host.filter({ $0 == ":" }).count == 1, let colon = host.lastIndex(of: ":") {
            port = UInt16(host[host.index(after: colon)...])
            host = String(host[..<colon])
        }
        guard !host.isEmpty else { return nil }
        switch share.proto {
        case .nfs: return (host, port ?? 2049)
        case .smb: return (host, port ?? 445)
        case .webdav: return (host, port ?? (share.https ? 443 : 80))
        case .s3: return (host, port ?? 443)
        }
    }
}

// MARK: - Store

/// Per-share bookkeeping for the availability watcher.
struct WatchState {
    var reachable: Bool?        // nil until the first check
    var failures = 0            // consecutive failed checks
    var wantMounted = false     // server (re)appeared and we still owe it a mount
    var attempts = 0            // mount attempts since it appeared
}

@MainActor
final class Store: ObservableObject {
    /// Shared by the windows and the menu bar item.
    static let shared = Store()

    @Published var shares: [Share] = []
    @Published var busy: Set<String> = []
    /// Human-readable watcher state per share ("Waiting for server…", failures).
    @Published var autoStatus: [String: String] = [:]

    private var pollTask: Task<Void, Never>?
    private var watchTask: Task<Void, Never>?
    private var watch: [String: WatchState] = [:]
    private var ticking = false
    private let pathMonitor = NWPathMonitor()

    /// Keeps mount state fresh for the menu bar item even when no window is open.
    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    /// Errors need to be visible whether triggered from a window or the menu bar.
    func showError(_ message: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Mountie"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    /// Re-reads the config file and the current mount state.
    func reload() async {
        let loaded = Ctl.loadShares()
        let listing = await Ctl.run(["list"], timeout: 10)
        // A listing that failed (or was cut off at the cap) says nothing about the mounts —
        // treating it as "nothing mounted" would flip every share and tear the sidebar down.
        guard listing.ok else { return }
        var state: [String: String] = [:]
        for line in listing.out.split(whereSeparator: \.isNewline) {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false)
            if f.count >= 2 { state[String(f[0])] = String(f[1]) }
        }
        let auto = Prefs.autoShares, tailscale = Prefs.tailscaleShares,
            wifi = Prefs.wifiNetworks, tsAccounts = Prefs.tailscaleAccounts
        let updated = loaded.map { s -> Share in
            var s = s
            s.mounted = state[s.name] == "mounted"
            s.auto = auto.contains(s.name)
            s.viaTailscale = s.auto && tailscale.contains(s.name)
            s.tailscaleAccounts = s.auto ? (tsAccounts[s.name] ?? []) : []
            s.wifiNetworks = s.auto ? (wifi[s.name] ?? []) : []
            return s
        }
        if updated != shares { shares = updated }
        reconcileSidebar()
    }

    // MARK: Finder sidebar

    /// Adds the share's folder to Finder's Favorites, remembering only entries Mountie
    /// added itself (a favorite the user dragged there by hand is never recorded, and so
    /// never removed). Returns false when the entry already exists.
    @discardableResult
    private func sidebarAdd(_ name: String) -> Bool {
        guard Sidebar.add(name, owned: Prefs.sidebarShares.contains(name)) else { return false }
        Prefs.sidebarShares.insert(name)
        return true
    }

    /// Removes the sidebar entry Mountie added for this share, if there is one. The record is
    /// only dropped once the entry is really gone — a failed removal (e.g. the entry's bookmark
    /// died when unmount removed the folder) is retried by the next reconcile pass.
    private func sidebarRemove(_ name: String) {
        guard Prefs.sidebarShares.contains(name) else { return }
        if Sidebar.remove(name) { Prefs.sidebarShares.remove(name) }
    }

    /// Keeps Favorites in step with what's actually mounted, healing drift from reboots
    /// (favorites persist, mounts don't), CLI mounts/unmounts, and deleted entries:
    /// everything mounted is in the sidebar, everything else isn't.
    private func reconcileSidebar() {
        for s in shares where s.mounted { sidebarAdd(s.name) }
        for name in Prefs.sidebarShares
        where !shares.contains(where: { $0.name == name && $0.mounted }) {
            sidebarRemove(name)
        }
    }

    /// How long one unmount helper may run. Above mountiectl's own two capped steps (8 s
    /// each) plus its rclone stop, so its specific message ("still in use", "server isn't
    /// answering") reaches the user rather than the app's generic timeout.
    nonisolated static let unmountCap: TimeInterval = 20

    func toggle(_ share: Share) async {
        busy.insert(share.name)
        defer { busy.remove(share.name) }
        if share.mounted { await unmount(share); return }
        // S3 goes through rclone, which gets its credentials from the environment.
        let s3 = share.proto == .s3 ? S3Keys.env(for: share.name) : nil
        if let problem = await Preflight.problem(for: share) {
            showError(problem)
            return
        }
        // No cap on a mount: it may sit in a sign-in dialog, and rclone shares the helper's
        // process group (see Ctl.run).
        let r = await Ctl.run(["mount", share.name], extraEnv: s3)
        if !r.ok {
            await reload()
            showError(r.err.isEmpty ? "The operation failed." : r.err)
            return
        }
        _ = sidebarAdd(share.name)
        _ = await Ctl.run(["reveal", share.name])
        await reload()
    }

    /// A manual unmount: capped, and when the share won't go (files open in another app, a
    /// server that stopped answering) the user decides — try again, force, or leave it.
    private func unmount(_ share: Share) async {
        var force = false
        while true {
            let args = ["unmount", share.name] + (force ? ["force"] : [])
            let r = await Ctl.run(args, timeout: Self.unmountCap)
            await reload()
            let still = shares.first { $0.name == share.name }?.mounted ?? false
            if r.ok || !still { sidebarRemove(share.name); return }
            if force {
                showError(r.err.isEmpty ? "The share couldn't be unmounted." : r.err)
                return
            }
            switch StuckShares.ask([share.name], detail: r.err, keep: "Cancel", cancel: false) {
            case .tryAgain: continue
            case .force: force = true
            case .keep, .cancel: return
            }
        }
    }

    func reveal(_ share: Share) async { _ = await Ctl.run(["reveal", share.name]) }

    /// One quit-time unmount round: every mounted share in parallel, force only when the user
    /// asked for it in the quit dialog. Returns the names that are still mounted afterwards
    /// (each helper is capped — a vanished server can hang an unmount indefinitely, and a
    /// capped share counts as stuck). Shares already busy (an unmount in flight from the
    /// menu, or an earlier round the user cancelled) are left to that operation and count
    /// as stuck for this one.
    func unmountAll(force: Bool, timeout: TimeInterval = Store.unmountCap) async -> [String] {
        let mounted = shares.filter(\.mounted)
        guard !mounted.isEmpty else { return [] }
        var gone: [String] = [], stuck: [String] = []
        let todo = mounted.filter { !busy.contains($0.name) }
        stuck += mounted.filter { busy.contains($0.name) }.map(\.name)
        for share in todo { busy.insert(share.name) }
        await withTaskGroup(of: (String, Bool).self) { group in
            for share in todo {
                group.addTask {
                    let args = force ? ["unmount", share.name, "force"] : ["unmount", share.name]
                    return (share.name, await Ctl.run(args, timeout: timeout).ok)
                }
            }
            for await (name, ok) in group {
                busy.remove(name)
                if ok { gone.append(name) } else { stuck.append(name) }
            }
        }
        for name in gone { sidebarRemove(name) }
        return stuck
    }

    func save(_ share: Share, replacing oldName: String?) {
        var share = share
        if !share.auto { share.viaTailscale = false; share.tailscaleAccounts = []; share.wifiNetworks = [] }
        var list = shares
        if let oldName, let i = list.firstIndex(where: { $0.name == oldName }) {
            list[i] = share
        } else {
            list.append(share)
        }
        guard write(list) else { return }
        var auto = Prefs.autoShares, tailscale = Prefs.tailscaleShares,
            wifi = Prefs.wifiNetworks, tsAccounts = Prefs.tailscaleAccounts
        if let oldName { auto.remove(oldName); tailscale.remove(oldName); wifi[oldName] = nil; tsAccounts[oldName] = nil }
        if share.auto { auto.insert(share.name) }
        if share.viaTailscale { tailscale.insert(share.name) }
        wifi[share.name] = share.wifiNetworks.isEmpty ? nil : share.wifiNetworks
        tsAccounts[share.name] = share.tailscaleAccounts.isEmpty ? nil : share.tailscaleAccounts
        if let oldName { Prefs.sidebarShares.remove(oldName) }   // rename: defensive, only unmounted shares can be edited
        Prefs.autoShares = auto
        Prefs.tailscaleShares = tailscale
        Prefs.wifiNetworks = wifi
        Prefs.tailscaleAccounts = tsAccounts
        Task { await watchTick() }   // apply the new setting right away
    }

    func remove(_ share: Share) {
        guard write(shares.filter { $0.name != share.name }) else { return }
        Prefs.autoShares.remove(share.name)
        Prefs.tailscaleShares.remove(share.name)
        Prefs.tailscaleAccounts[share.name] = nil
        Prefs.wifiNetworks[share.name] = nil
        Prefs.sidebarShares.remove(share.name)
        if share.proto == .s3 { S3Keys.delete(share.name) }
    }

    @discardableResult
    private func write(_ list: [Share]) -> Bool {
        do {
            try Ctl.save(list)
            shares = list
            return true
        } catch {
            showError("Couldn't save the configuration: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Availability watcher

    /// Checks shares marked "auto" every few seconds, and immediately when the network
    /// changes or the Mac wakes up.
    func startWatching() {
        guard watchTask == nil else { return }
        watchTask = Task {
            while !Task.isCancelled {
                await watchTick()
                try? await Task.sleep(for: .seconds(Prefs.watchInterval))
            }
        }
        pathMonitor.pathUpdateHandler = { _ in Task { @MainActor in await Store.shared.watchTick() } }
        pathMonitor.start(queue: .global())
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in Task { @MainActor in await Store.shared.watchTick() } }
    }

    /// One watcher pass. Acts on *changes* in availability rather than on state, so a share
    /// you unmount by hand stays unmounted until its server goes away and comes back.
    func watchTick() async {
        guard !ticking else { return }
        ticking = true
        defer { ticking = false }

        await reload()
        let targets = shares.filter(\.auto)
        let names = Set(targets.map(\.name))
        watch = watch.filter { names.contains($0.key) }
        autoStatus = autoStatus.filter { names.contains($0.key) }
        guard !targets.isEmpty else { return }

        // No Location access = automatic mounting is off: touch nothing, and say why.
        guard WiFi.locationGranted else {
            for s in targets { autoStatus[s.name] = "Automatic mounting is off: allow Location access in Preferences." }
            return
        }

        var tailscaleRunning = false, tailscaleTailnet: String?
        if targets.contains(where: \.viaTailscale) {
            let r = await Ctl.run(["tailscale"], timeout: 10)
            tailscaleRunning = r.ok
            tailscaleTailnet = r.ok ? Tailscale.parseTailnet(r.out) : nil
        }
        let ssid = targets.contains(where: { !$0.wifiNetworks.isEmpty }) ? WiFi.currentSSID() : nil
        var waiting: [String: String] = [:]
        for s in targets {
            if s.proto == .s3 && S3Keys.load(s.name) == nil {
                waiting[s.name] = "S3 keys missing: edit the share and add them."
            } else if let reason = s.unavailableReason(tailscaleRunning: tailscaleRunning,
                                                     tailscaleTailnet: tailscaleTailnet, ssid: ssid) {
                waiting[s.name] = reason
            }
        }

        let blocked = Set(waiting.keys)
        let reachable: [String: Bool] = await withTaskGroup(of: (String, Bool).self) { group in
            for s in targets {
                let skip = blocked.contains(s.name)   // conditions not met = unavailable, no need to probe
                let s3 = s.proto == .s3 ? S3Keys.env(for: s.name) : nil
                group.addTask { (s.name, skip ? false : await Ctl.run(["probe", s.name], extraEnv: s3, timeout: 15).ok) }
            }
            var result: [String: Bool] = [:]
            for await (name, ok) in group { result[name] = ok }
            return result
        }
        for s in targets {
            await apply(s.name, reachable: reachable[s.name] ?? false, waiting: waiting[s.name])
        }
        await reload()
    }

    private func apply(_ name: String, reachable ok: Bool, waiting: String?) async {
        guard let cur = shares.first(where: { $0.name == name }), cur.auto else { return }
        var st = watch[name] ?? WatchState()
        defer { watch[name] = st }

        if ok {
            st.failures = 0
            if st.reachable != true {              // just appeared (or first check)
                st.reachable = true
                st.wantMounted = true
                st.attempts = 0
            }
            if cur.mounted {
                st.wantMounted = false
                autoStatus[name] = nil
            } else if st.wantMounted && !busy.contains(name) {
                let s3 = cur.proto == .s3 ? S3Keys.env(for: name) : nil
                // Reachable only says the server's port answers — after a restart it
                // does so long before the share will mount, and mounting then just
                // produces I/O errors. "ready" checks that a mount can actually
                // happen, without mounting anything.
                guard await Ctl.run(["ready", name], extraEnv: s3, timeout: 15).ok else {
                    autoStatus[name] = "Server is up; the share isn't ready yet — retrying…"
                    return
                }
                busy.insert(name)
                if let problem = await Preflight.problem(for: cur) {
                    busy.remove(name)
                    st.attempts += 1
                    autoStatus[name] = "Auto-mount failed: " + problem
                    st.wantMounted = st.attempts < 5 || (st.attempts - 5) % 10 == 0
                    return
                }
                // "quiet": never pop a sign-in dialog for an automatic mount.
                let r = await Ctl.run(["mount", name, "quiet"], extraEnv: s3)
                busy.remove(name)
                if r.ok {
                    st.wantMounted = false
                    autoStatus[name] = nil
                    _ = sidebarAdd(name)
                } else {
                    st.attempts += 1
                    autoStatus[name] = "Auto-mount failed: " + (r.err.isEmpty ? "unknown error" : r.err)
                    // A mount can still fail on a reachable server (server restarting,
                    // SMB needs a sign-in, the export refuses this client). Never give
                    // up for good — that would strand the share until the server went
                    // away and came back — but throttle: a few quick tries, then one
                    // per 10 passes.
                    st.wantMounted = st.attempts < 5 || (st.attempts - 5) % 10 == 0
                }
            }
        } else {
            st.failures += 1
            // Two misses in a row before we act, so a single dropped probe doesn't unmount anything.
            if st.failures >= 2 {
                if st.reachable != false {         // just disappeared
                    st.reachable = false
                    st.wantMounted = false
                    if cur.mounted && !busy.contains(name) {
                        busy.insert(name)
                        // Capped: the server is gone, so a umount can hang, and a hung one
                        // would hold `ticking` and stop the watcher for good.
                        let r = await Ctl.run(["unmount", name, "force"], timeout: 15)
                        busy.remove(name)
                        if r.ok { sidebarRemove(name) }
                    }
                }
            }
            if st.failures >= 2 || !cur.mounted {
                autoStatus[name] = waiting ?? "Waiting for server…"
            }
        }
    }
}

/// The "couldn't unmount" dialog, shared by the manual unmount and the quit. Modal on purpose:
/// the operation is on hold until the user decides. `keep` titles the third button ("Cancel"
/// for a manual unmount, "Keep Mounted" when quitting, where a separate Cancel stays running).
/// Esc is the last button — leaving things as they are is the least destructive escape.
enum StuckShares {
    enum Choice { case tryAgain, force, keep, cancel }

    @MainActor
    static func ask(_ names: [String], detail: String?, keep: String, cancel: Bool) -> Choice {
        NSApp.activate()
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = names.count == 1
            ? "Couldn't unmount “\(names[0])”."
            : "Couldn't unmount \(names.count) shares."
        var info = names.count == 1 ? "" : names.joined(separator: ", ") + "\n\n"
        // The helper's own message says what's wrong ("still in use", "server isn't
        // answering"); the generic advice is for when there is none (the quit round).
        if let detail, !detail.isEmpty {
            info += detail
        } else {
            info += "Files on these shares may be open in other apps. Close them and try again, or force the unmount."
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Try Again")
        alert.addButton(withTitle: "Force Unmount")
        alert.addButton(withTitle: keep)
        if cancel { alert.addButton(withTitle: "Cancel") }
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .tryAgain
        case .alertSecondButtonReturn: return .force
        case .alertThirdButtonReturn: return .keep
        default: return .cancel
        }
    }
}

// MARK: - Windows and main menu

/// Menu-bar-only apps have no main menu, so ⌘C/⌘V/⌘W wouldn't work in our windows without one.
@MainActor
enum AppMenu {
    static func install() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem()
            main.addItem(item)
            let menu = NSMenu(title: title)
            item.submenu = menu
            return menu
        }
        func add(_ menu: NSMenu, _ title: String, _ action: Selector, _ key: String,
                 _ mods: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            menu.addItem(item)
        }

        let app = submenu("Mountie")
        add(app, "Preferences…", #selector(AppDelegate.showPreferences), ",")
        #if RELEASE
        add(app, "Check for Updates…", #selector(AppDelegate.checkForUpdates), "")
        #endif
        app.addItem(.separator())
        add(app, "Quit Mountie", #selector(NSApplication.terminate(_:)), "q")

        let edit = submenu("Edit")
        add(edit, "Undo", Selector(("undo:")), "z")
        add(edit, "Redo", Selector(("redo:")), "z", [.command, .shift])
        edit.addItem(.separator())
        add(edit, "Cut", #selector(NSText.cut(_:)), "x")
        add(edit, "Copy", #selector(NSText.copy(_:)), "c")
        add(edit, "Paste", #selector(NSText.paste(_:)), "v")
        add(edit, "Select All", #selector(NSText.selectAll(_:)), "a")

        let window = submenu("Window")
        add(window, "Close", #selector(NSWindow.performClose(_:)), "w")
        add(window, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")

        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }
}

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var windows: [String: NSWindow] = [:]

    func showManage() {
        present("manage", title: "Mountie", size: NSSize(width: 600, height: 500), resizable: true) {
            ContentView()
        }
    }

    func showPreferences() {
        present("prefs", title: "Preferences", size: NSSize(width: 460, height: 580), resizable: false) {
            PreferencesView()
        }
    }

    private func present<V: View>(_ key: String, title: String, size: NSSize, resizable: Bool,
                                  @ViewBuilder content: () -> V) {
        AppMenu.install()
        if windows[key] == nil {
            var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable]
            if resizable { style.insert(.resizable) }
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style,
                             backing: .buffered, defer: false)
            w.contentViewController = NSHostingController(rootView: content())
            w.title = title
            w.isReleasedWhenClosed = false
            w.setContentSize(size)
            w.center()
            if resizable { w.setFrameAutosaveName("Mountie.\(key)") }
            windows[key] = w
        }
        NSApp.activate()
        windows[key]?.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Views

enum EditTarget: Identifiable {
    case new
    case edit(Share)
    var id: String {
        switch self {
        case .new: "new"
        case .edit(let s): s.name
        }
    }
}

struct ContentView: View {
    @ObservedObject private var store = Store.shared
    @State private var editing: EditTarget?
    @State private var pendingRemoval: Share?

    private func openEditor(_ original: Share?) {
        editing = original.map { .edit($0) } ?? .new
    }

    var body: some View {
        Group {
            if store.shares.isEmpty {
                ContentUnavailableView {
                    Label("No Shares", systemImage: "externaldrive.connected.to.line.below")
                } description: {
                    Text("Add an NFS, SMB, WebDAV or S3 share to mount and unmount it with one click.")
                } actions: {
                    Button("Add Share…") { openEditor(nil) }.buttonStyle(.borderedProminent)
                }
            } else {
                List(store.shares) { share in
                    ShareRow(share: share, busy: store.busy.contains(share.name),
                             status: store.autoStatus[share.name],
                             toggle: { Task { await store.toggle(share) } },
                             reveal: { Task { await store.reveal(share) } },
                             edit: { openEditor(share) },
                             remove: { pendingRemoval = share })
                }
            }
        }
        // Tall enough that the editor sheet (which can't exceed this window) shows every setting.
        .frame(minWidth: 540, minHeight: 500)
        .toolbar {
            ToolbarItem {
                Button { WindowManager.shared.showPreferences() } label: {
                    Label("Preferences", systemImage: "gearshape")
                }
                .help("Preferences")
            }
            ToolbarItem {
                Button { openEditor(nil) } label: { Label("Add Share", systemImage: "plus") }
                    .help("Add a share")
            }
        }
        .sheet(item: $editing) { target in
            let original: Share? = if case .edit(let s) = target { s } else { nil }
            ShareEditor(original: original,
                        takenNames: Set(store.shares.map { $0.name.lowercased() }),
                        onSave: { saved in store.save(saved, replacing: original?.name) },
                        close: { editing = nil })
        }
        .confirmationDialog(
            "Remove “\(pendingRemoval?.name ?? "")”?",
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let s = pendingRemoval { store.remove(s) }
                pendingRemoval = nil
            }
        } message: {
            Text("This only removes it from this list. Nothing on the server is deleted.")
        }
        .task { await store.reload() }   // fresh state whenever the window opens
        // Sheets, popovers and dialogs consume Esc themselves (cancel), so this only fires
        // when nothing like that is open — then Esc closes the window, like ⌘W.
        .onExitCommand { NSApp.keyWindow?.performClose(nil) }
    }
}

struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}

/// Icon-only buttons: a hit-area pad instead of text-button chrome, pressed and disabled fades.
private struct IconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(3)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.4 : isEnabled ? 1 : 0.35)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var imageButton: IconButtonStyle { IconButtonStyle() }
}

struct ShareRow: View {
    let share: Share
    let busy: Bool
    let status: String?
    let toggle: () -> Void
    let reveal: () -> Void
    let edit: () -> Void
    let remove: () -> Void

    private var autoLabel: String {
        var parts = ["Auto"]
        if share.viaTailscale { parts.append("Tailscale") }
        if !share.wifiNetworks.isEmpty { parts.append("Wi-Fi") }
        return parts.joined(separator: " · ")
    }

    private var autoHelp: String {
        var when: [String] = []
        if share.viaTailscale {
            when.append(share.tailscaleAccounts.isEmpty
                         ? "Tailscale is running"
                         : "Tailscale runs as \(share.tailscaleAccounts.joined(separator: ", "))")
        }
        if !share.wifiNetworks.isEmpty { when.append("connected to \(share.wifiNetworks.joined(separator: ", "))") }
        let base = "Mounts and unmounts automatically as the server comes and goes"
        return when.isEmpty ? base : base + ", while " + when.joined(separator: " or ")
    }

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(share.mounted ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 10, height: 10)
                .accessibilityLabel(share.mounted ? "Mounted" : "Not mounted")
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(share.name).font(.headline)
                    Pill(text: share.proto.label)
                    if share.auto { Pill(text: autoLabel).help(autoHelp) }
                }
                Text(share.proto == .nfs ? "\(share.displaySpec)  ·  \(share.displayOptions)" : share.displaySpec)
                    .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                if share.proto == .s3 && S3Keys.load(share.name) == nil {
                    Text("S3 keys missing").font(.caption).foregroundStyle(.orange)
                }
                if let status {
                    Text(status).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            // All of the share's actions in one pill, so there's no menu to dig through.
            HStack(spacing: 10) {
                Button(action: toggle) {
                    Image(systemName: share.mounted ? "arrow.up.circle" : "arrow.down.circle")
                }
                .help(share.mounted ? "Unmount" : "Mount")
                .accessibilityLabel(share.mounted ? "Unmount" : "Mount")
                .disabled(busy)
                Button(action: reveal) { Image(systemName: "folder") }
                    .help("Open in Finder")
                    .accessibilityLabel("Open in Finder")
                    .disabled(!share.mounted)
                Button(action: edit) { Image(systemName: "pencil") }
                    .help(share.mounted ? "Unmount to edit this share" : "Edit…")
                    .accessibilityLabel("Edit")
                    .disabled(share.mounted)
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
                    .help(share.mounted ? "Unmount to remove this share" : "Remove…")
                    .accessibilityLabel("Remove")
                    .disabled(share.mounted)
            }
            .buttonStyle(.imageButton)
            .padding(.horizontal, 7).padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Show in Finder", action: reveal).disabled(!share.mounted)
            Button("Edit…", action: edit).disabled(share.mounted)
            Button("Remove…", role: .destructive, action: remove).disabled(share.mounted)
        }
    }
}

/// Explains, and offers to fix, missing Location access, which automatic mounting requires.
struct LocationNotice: View {
    @ObservedObject private var location = LocationAccess.shared

    var body: some View {
        switch location.status {
        case .notDetermined:
            VStack(alignment: .leading, spacing: 6) {
                Text("Automatic mounting needs Location access: macOS only tells an app which Wi-Fi network you're on if it has it. Nothing else about your location is used.")
                Button("Allow Location Access") { location.request() }
            }
            .font(.callout)
        case .denied, .restricted:
            VStack(alignment: .leading, spacing: 6) {
                Text("Location access is off, so automatic mounting is disabled.")
                Button("Open Privacy Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .font(.callout).foregroundStyle(.orange)
        default:
            EmptyView()
        }
    }
}

/// Multi-select list of Wi-Fi networks this Mac has already joined.
struct WifiPicker: View {
    @Binding var selected: [String]
    @State private var query = ""
    private let known = WiFi.knownNetworks()
    private let current = WiFi.currentSSID()

    private var rows: [String] {
        let all = Set(known).union(selected).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return query.isEmpty ? all : all.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private func binding(_ ssid: String) -> Binding<Bool> {
        Binding(get: { selected.contains(ssid) },
                set: { on in
                    if on { if !selected.contains(ssid) { selected.append(ssid); selected.sort() } }
                    else { selected.removeAll { $0 == ssid } }
                })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Wi-Fi networks").font(.headline)
            Text("Only networks this Mac has joined before are listed.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
            if rows.isEmpty {
                Text(known.isEmpty ? "This Mac hasn't joined any Wi-Fi networks yet." : "No matches.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                List(rows, id: \.self) { ssid in
                    Toggle(isOn: binding(ssid)) {
                        HStack(spacing: 6) {
                            Text(ssid)
                            if ssid == current { Pill(text: "connected") }
                            if !known.contains(ssid) { Pill(text: "not remembered") }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .frame(width: 340)
    }
}

/// The Tailscale-account picker for the Automatic tab, mirroring the Wi-Fi one. The
/// choices come from the Tailscale CLI (via mountiectl), which takes a moment, so
/// they load when the popover appears rather than at editor init.
struct TailscalePicker: View {
    @Binding var selected: [String]   // tailnet names; the network identity behind an account
    @State private var accounts: [Tailscale.Account]?
    @State private var failed = false
    @State private var query = ""

    /// One row per tailnet (that's what the choice is matched on), with the chosen
    /// tailnets kept even when they're no longer signed in, so they can be unchecked.
    private var rows: [Tailscale.Account] {
        let listed = accounts ?? []
        let known = Set(listed.map(\.tailnet))
        var all = listed + selected.filter { !known.contains($0) }
            .map { Tailscale.Account(id: $0, nickname: $0, tailnet: $0, account: $0) }
        all.sort { $0.account.localizedCaseInsensitiveCompare($1.account) == .orderedAscending }
        return query.isEmpty ? all
            : all.filter { $0.account.localizedCaseInsensitiveContains(query)
                         || $0.tailnet.localizedCaseInsensitiveContains(query) }
    }

    private func binding(_ tailnet: String) -> Binding<Bool> {
        Binding(get: { selected.contains(tailnet) },
                set: { on in
                    if on { if !selected.contains(tailnet) { selected.append(tailnet); selected.sort() } }
                    else { selected.removeAll { $0 == tailnet } }
                })
    }

    private var signedIn: Set<String> {
        Set((accounts ?? []).map(\.tailnet))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tailscale accounts").font(.headline)
            Text("Only one of the accounts set up in the Tailscale app is active at a time.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.leading)
            if accounts == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if rows.isEmpty {
                Text(failed
                     ? "Couldn't list accounts — Tailscale's app or CLI isn't available. Any account will be used."
                     : "No Tailscale accounts are set up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                List(rows, id: \.tailnet) { a in
                    Toggle(isOn: binding(a.tailnet)) {
                        HStack(spacing: 6) {
                            Text(a.account)
                            if a.tailnet != a.account {
                                Text(a.tailnet).font(.caption).foregroundStyle(.secondary)
                            }
                            if a.selected { Pill(text: "active") }
                            if !failed && !signedIn.contains(a.tailnet) { Pill(text: "not signed in") }
                        }
                    }
                }
                .frame(height: 200)
            }
        }
        .padding()
        .frame(width: 340)
        .task {
            if let a = await Tailscale.accounts() { accounts = a } else { failed = true; accounts = [] }
        }
    }
}

struct ShareEditor: View {
    enum Tab: String, CaseIterable, Identifiable {
        case share = "Share", automatic = "Automatic"
        var id: String { rawValue }
    }

    let original: Share?
    let takenNames: Set<String>
    let onSave: (Share) -> Void
    let close: () -> Void

    @ObservedObject private var location = LocationAccess.shared
    @State private var tab: Tab = .share
    @State private var proto: Proto
    @State private var name: String
    @State private var server: String
    @State private var path: String
    @State private var username: String
    @State private var https: Bool
    @State private var options: String
    @State private var auto: Bool
    @State private var viaTailscale: Bool
    @State private var tailscaleAccounts: [String]
    @State private var wifiNetworks: [String]
    @State private var showTailscalePicker = false
    @State private var showWifiPicker = false
    // S3 credentials, kept in the Keychain (see s3Keys view) — never part of the share itself.
    @State private var s3Endpoint: String
    @State private var s3Region: String
    @State private var s3AccessKey: String
    @State private var s3Secret: String
    @State private var s3Https: Bool

    init(original: Share?, takenNames: Set<String>, onSave: @escaping (Share) -> Void,
         close: @escaping () -> Void) {
        self.original = original
        self.takenNames = takenNames
        self.onSave = onSave
        self.close = close
        _proto = State(initialValue: original?.proto ?? .nfs)
        _name = State(initialValue: original?.name ?? "")
        _server = State(initialValue: original?.server ?? "")
        _path = State(initialValue: original?.path ?? "")
        _username = State(initialValue: original?.username ?? "")
        _https = State(initialValue: original?.https ?? true)
        _options = State(initialValue: original?.options ?? "")
        _auto = State(initialValue: original?.auto ?? false)
        _viaTailscale = State(initialValue: original?.viaTailscale ?? false)
        _tailscaleAccounts = State(initialValue: original?.tailscaleAccounts ?? [])
        _wifiNetworks = State(initialValue: original?.wifiNetworks ?? [])
        let k = original?.proto == .s3 ? S3Keys.load(original!.name) : nil
        _s3Endpoint = State(initialValue: k?.endpoint ?? "")
        _s3Region = State(initialValue: k?.region ?? "")
        _s3AccessKey = State(initialValue: k?.accessKey ?? "")
        _s3Secret = State(initialValue: k?.secret ?? "")
        _s3Https = State(initialValue: k?.https ?? true)
    }

    private var trimmed: (name: String, server: String, path: String, username: String, options: String) {
        func t(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces) }
        return (t(name), t(server), t(path), t(username), t(options))
    }

    private var pathLabel: String { proto == .smb ? "Share" : proto == .s3 ? "Bucket" : "Path" }
    private var pathPrompt: String {
        switch proto {
        case .nfs: "/volume1/media"
        case .smb: "Documents or Documents/Projects"
        case .webdav: "/remote.php/dav (optional)"
        case .s3: "photos or photos/2026"
        }
    }

    /// nil when valid. Messages for fields the user hasn't filled yet are suppressed in the UI.
    private var problem: (message: String, isMissingField: Bool)? {
        let t = trimmed
        if t.name.isEmpty || (proto != .s3 && t.server.isEmpty) || (proto != .webdav && t.path.isEmpty) {
            let msg = switch proto {
                case .smb: "Fill in name, server and share."
                case .s3: "Fill in name and bucket."
                default: "Fill in name and server\(proto == .webdav ? "." : " and path.")"
            }
            return (msg, true)
        }
        if t.name.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) == nil {
            return ("Name may only contain letters, numbers, dots, dashes and underscores.", false)
        }
        if takenNames.contains(t.name.lowercased()) && t.name.lowercased() != original?.name.lowercased() {
            return ("A share with this name already exists.", false)
        }
        switch proto {
        case .nfs:
            if t.server.contains(where: { $0.isWhitespace || $0 == ":" || $0 == "/" }) {
                return ("Server should be a host name or IP address only, e.g. nas.example.com.", false)
            }
            if !t.path.hasPrefix("/") {
                return ("Path must start with /, e.g. /volume1/media.", false)
            }
            if t.options.contains(where: \.isWhitespace) {
                return ("Options are comma-separated without spaces, e.g. ro,soft.", false)
            }
        case .smb, .webdav:
            if t.server.range(of: #"^[^\s/:@]+(:\d{1,5})?$"#, options: .regularExpression) == nil {
                return ("Server should be a host name or IP address, optionally with :port.", false)
            }
            if proto == .smb && (t.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).isEmpty || t.path.contains("\\")) {
                return ("Enter the share name, e.g. Documents (or Documents/Projects).", false)
            }
            if t.username.contains("/") || t.username.contains(":") {
                return ("Username can't contain / or :. The password is asked for by macOS.", false)
            }
        case .s3:
            let ep = s3Endpoint.trimmingCharacters(in: .whitespaces)
            if !ep.isEmpty && ep.range(of: #"^[^\s/:@]+(:\d{1,5})?$"#, options: .regularExpression) == nil {
                return ("Endpoint should be a host name or IP address, optionally with :port.", false)
            }
            if t.path.contains(where: \.isWhitespace) {
                return ("Bucket can't contain spaces, e.g. photos or photos/2026.", false)
            }
            let access = !s3AccessKey.trimmingCharacters(in: .whitespaces).isEmpty
            let secret = !s3Secret.isEmpty
            if access != secret {
                return ("Enter both the access key ID and the secret access key, or neither.", false)
            }
        }
        return nil
    }

    /// The S3 credentials as saved in the Keychain (nil if none were entered).
    private var s3Keys: S3Keys.Info? {
        s3AccessKey.trimmingCharacters(in: .whitespaces).isEmpty ? nil : S3Keys.Info(
            endpoint: s3Endpoint.trimmingCharacters(in: .whitespaces),
            region: s3Region.trimmingCharacters(in: .whitespaces),
            accessKey: s3AccessKey.trimmingCharacters(in: .whitespaces),
            secret: s3Secret, https: s3Https)
    }

    /// Saves/deletes the S3 keys when the share is saved, renamed, or stops being S3.
    private func persistS3Keys() {
        if let original, original.name != trimmed.name || proto != .s3 { S3Keys.delete(original.name) }
        guard proto == .s3 else { return }
        if let k = s3Keys { S3Keys.save(trimmed.name, k) }
        else if let original, original.name == trimmed.name { S3Keys.delete(trimmed.name) }   // keys cleared
    }

    private func makeShare() -> Share {
        let t = trimmed
        var p = t.path
        var server = t.server
        switch proto {
        case .nfs: break
        case .smb: p = p.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        case .webdav: if !p.isEmpty && !p.hasPrefix("/") { p = "/" + p }
        case .s3: p = p.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                  server = s3Endpoint.trimmingCharacters(in: .whitespaces)
                  if server.isEmpty { server = "s3.amazonaws.com" }   // keys decide the real endpoint
        }
        return Share(name: t.name, proto: proto, server: server, path: p,
                     username: proto == .nfs || proto == .s3 ? "" : t.username, https: https,
                     options: proto == .nfs ? t.options : "",
                     auto: auto, viaTailscale: auto && viaTailscale,
                     tailscaleAccounts: auto ? tailscaleAccounts : [],
                     wifiNetworks: auto ? wifiNetworks : [])
    }

    private var tsSummary: String {
        switch tailscaleAccounts.count {
        case 0: "Any account"
        case 1: tailscaleAccounts[0]
        default: "\(tailscaleAccounts.count) accounts"
        }
    }

    private var wifiSummary: String {
        switch wifiNetworks.count {
        case 0: "Choose…"
        case 1: wifiNetworks[0]
        default: "\(wifiNetworks.count) networks"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top])

            Form {
                switch tab {
                case .share: shareFields
                case .automatic: automaticFields
                }
            }
            .formStyle(.grouped)
            .onChange(of: tab) { _, newTab in
                // Ask at the moment the user reaches for automatic mounting, not before.
                if newTab == .automatic && location.status == .notDetermined { location.request() }
            }

            // Outside the Form so it stays visible however the form scrolls.
            VStack(alignment: .leading, spacing: 2) {
                Text("Mounts at \(Prefs.mountBase)/\(trimmed.name.isEmpty ? "name" : trimmed.name)")
                    .foregroundStyle(.secondary)
                if proto == .s3 && tab == .share {
                    Text("The keys are kept in your Keychain. macOS asks before Mountie can read them the first time.")
                        .foregroundStyle(.secondary)
                } else if proto != .nfs && tab == .share {
                    Text("The password isn't stored by this app: macOS asks for it the first time you mount, and can save it to your Keychain.")
                        .foregroundStyle(.secondary)
                }
                if let p = problem, !p.isMissingField {
                    Text(p.message).foregroundStyle(.red)
                }
            }
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 30)
            .padding(.bottom)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { close() }.keyboardShortcut(.cancelAction)
                Button(original == nil ? "Add" : "Save") {
                    persistS3Keys()
                    onSave(makeShare())
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil)
            }
            .padding([.horizontal, .bottom])
        }
        // A grouped Form doesn't report its content height, so the sheet needs an explicit one.
        .frame(width: 480, height: proto == .s3 ? 560 : 490)
    }

    @ViewBuilder private var shareFields: some View {
        Picker("Protocol", selection: $proto) {
            ForEach(Proto.allCases) { Text($0.label).tag($0) }
        }
        TextField("Name", text: $name, prompt: Text("media"))
        if proto != .s3 {
            TextField("Server", text: $server,
                      prompt: Text(proto == .webdav ? "dav.example.com" : proto == .smb ? "nas.example.com" : "nas.example.com or 10.0.0.5"))
        }
        TextField(pathLabel, text: $path, prompt: Text(pathPrompt))
        if proto == .smb || proto == .webdav {
            TextField("Username", text: $username, prompt: Text("optional"))
        }
        if proto == .webdav {
            Toggle("Use HTTPS", isOn: $https)
        }
        if proto == .nfs {
            Section {
                TextField("Options", text: $options, prompt: Text("soft"))
            } footer: {
                Text("Optional mount_nfs options, e.g. ro,soft or vers=4. Empty means soft.")
            }
        }
        if proto == .s3 { s3Fields }
    }

    /// The endpoint and keys live in the Keychain, not in the share; empty endpoint = Amazon S3.
    @ViewBuilder private var s3Fields: some View {
        Section {
            TextField("Endpoint", text: $s3Endpoint,
                      prompt: Text("leave empty for Amazon S3, or host[:port]"))
            TextField("Region", text: $s3Region, prompt: Text("us-east-1 (optional)"))
            SecureField("Access Key ID", text: $s3AccessKey)
            SecureField("Secret Access Key", text: $s3Secret)
            if !s3Endpoint.trimmingCharacters(in: .whitespaces).isEmpty {
                Toggle("Use HTTPS", isOn: $s3Https)
            }
        } footer: {
            Text("Keys are stored in your Keychain, never on disk. Leave the endpoint empty for Amazon S3; a host[:port] also works for Minio, Wasabi and other S3-compatible services.")
        }
    }

    @ViewBuilder private var automaticFields: some View {
        let granted = WiFi.locationGranted
        if !granted {
            Section { LocationNotice() }
        }
        Section {
            Toggle("Mount automatically when available", isOn: $auto)
                .disabled(!granted)
        } footer: {
            Text("Watches the server: mounts the share when it becomes reachable and unmounts it when it goes away.")
        }
        if granted {
            conditionFields
        }
    }

    @ViewBuilder private var conditionFields: some View {
        Section {
            Toggle("Tailscale is running", isOn: $viaTailscale)
            if viaTailscale {
                LabeledContent("Tailscale account") {
                    Button(tsSummary) { showTailscalePicker = true }
                        .popover(isPresented: $showTailscalePicker, arrowEdge: .bottom) {
                            TailscalePicker(selected: $tailscaleAccounts)
                        }
                }
            }
            LabeledContent("Connected to Wi-Fi") {
                Button(wifiSummary) { showWifiPicker = true }
                    .popover(isPresented: $showWifiPicker, arrowEdge: .bottom) {
                        WifiPicker(selected: $wifiNetworks)
                    }
            }
        } header: {
            Text("Only when")
        } footer: {
            Text("Leave both off to watch on any network. If you set both, either one is enough, for example your home Wi-Fi, or Tailscale when you're away. Narrow Tailscale down to chosen accounts if the share only exists in one of them. When no condition applies, the share is unmounted.")
        }
        .disabled(!auto)
    }
}

struct PreferencesView: View {
    @AppStorage(Prefs.hideWindowOnLaunch) private var hideWindow = false
    @AppStorage(Prefs.unmountOnQuitKey) private var unmountOnQuit = true
    @ObservedObject private var location = LocationAccess.shared
    @ObservedObject private var store = Store.shared
    @State private var mountBase = Prefs.mountBase
    @State private var folderError: String?
    @State private var startAtLogin = false
    @State private var needsApproval = false
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Start at login", isOn: Binding(get: { startAtLogin }, set: setStartAtLogin))
                if needsApproval {
                    HStack {
                        Text("Approve Mountie in System Settings → Login Items.")
                            .font(.callout).foregroundStyle(.orange)
                        Spacer()
                        Button("Open Settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                }
                Toggle("Hide window on start", isOn: $hideWindow)
                Toggle("Unmount all shares on quit", isOn: $unmountOnQuit)
            } footer: {
                Text("With “Hide window on start”, the app opens as a menu bar item only. Opening the app again while it's running shows the window. With “Unmount all shares on quit” off, shares stay mounted after Mountie exits — launch it again to manage them.")
            }
            Section {
                LabeledContent("Folder") {
                    HStack(spacing: 8) {
                        Text(mountBase).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                        Button("Reset") { applyFolder(Prefs.defaultMountBase) }
                            .disabled(mountBase == Prefs.defaultMountBase)
                    }
                    .disabled(anyMounted)
                }
                if anyMounted {
                    Text("Unmount all shares to change the folder.").font(.callout).foregroundStyle(.secondary)
                }
                if let folderError {
                    Text(folderError).font(.callout).foregroundStyle(.red)
                }
            } header: {
                Text("Shares folder")
            } footer: {
                Text("Each share mounts in its own subfolder here, for example \(mountBase)/NAS.")
            }
            Section {
                LabeledContent("Location access") {
                    Text(location.isAuthorized ? "Allowed" : location.status == .notDetermined ? "Not asked yet" : "Off")
                        .foregroundStyle(location.isAuthorized ? .green : .secondary)
                }
                LocationNotice()
            } header: {
                Text("Automatic mounting")
            } footer: {
                Text("Without Location access, automatic mounting is off.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .onAppear(perform: refreshLoginState)
        .onExitCommand { NSApp.keyWindow?.performClose(nil) }   // Esc closes, like ⌘W
    }

    private var anyMounted: Bool { store.shares.contains(where: \.mounted) }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose the folder Mountie mounts your shares in. Each share gets its own subfolder."
        var start = URL(fileURLWithPath: Prefs.mountBasePath)
        while !FileManager.default.fileExists(atPath: start.path) && start.path != "/" { start.deleteLastPathComponent() }
        panel.directoryURL = start
        if panel.runModal() == .OK, let url = panel.url { applyFolder(url.path) }
    }

    private func applyFolder(_ path: String) {
        guard !anyMounted else { return }   // moving the folder under a mounted share would orphan it
        if let problem = Prefs.problemWithMountBase(path) {
            folderError = problem
            return
        }
        folderError = nil
        Prefs.mountBase = ((path as NSString).expandingTildeInPath as NSString).abbreviatingWithTildeInPath
        mountBase = Prefs.mountBase
        Task { await store.reload() }
    }

    private func refreshLoginState() {
        let status = SMAppService.mainApp.status
        startAtLogin = status == .enabled || status == .requiresApproval
        needsApproval = status == .requiresApproval
    }

    private func setStartAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        refreshLoginState()
    }
}

// MARK: - App

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppMenu.install()
        Store.shared.startPolling()
        Store.shared.startWatching()
        if !UserDefaults.standard.bool(forKey: Prefs.hideWindowOnLaunch) {
            WindowManager.shared.showManage()
        }
    }

    /// Fired when the app is opened again (Finder, Spotlight, `open`) while already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.showManage()
        return true
    }

    // The menu bar item keeps the app alive after the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Quitting unmounts everything Mountie mounted (unless the user turned that off in
    /// Preferences). The graceful pass runs as capped helper processes; whatever is still
    /// mounted then is the user's call, not ours: a dialog offers Try Again (after closing
    /// the files holding the share), Force Unmount, Keep Mounted, or Cancel — no silent
    /// force. Force and Keep let the quit proceed; whatever survives a force stays mounted
    /// rather than blocking the quit forever.
    ///
    /// `.terminateLater` on purpose: AppKit then runs the loop in the modal-panel mode, in
    /// which main-actor tasks and alerts still run, and log out / shut down keep waiting for
    /// us instead of being cancelled (which `.terminateCancel` would do). What the user must
    /// not get is a frozen app with nothing on screen, so the round shows a cancelable
    /// "Unmounting…" alert as soon as it takes more than a moment.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = Store.shared
        guard Prefs.unmountOnQuit, store.shares.contains(where: \.mounted) else {
            return .terminateNow
        }
        let interactive = !Self.quitIsSystemInitiated
        Task { @MainActor in
            sender.reply(toApplicationShouldTerminate: await Self.quitRound(store, interactive: interactive))
        }
        return .terminateLater
    }

    /// Log out, restart and shut down send Quit with a reason; ⌘Q, the Dock and the menu don't.
    /// The system is waiting on us then, so no dialogs: one bounded best-effort pass.
    private static var quitIsSystemInitiated: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication),
              let why = event.paramDescriptor(forKeyword: AEKeyword(kAEQuitReason)) else { return false }
        let reasons = [kAELogOut, kAEReallyLogOut, kAEShutDown, kAERestart].map { OSType($0) }
        return reasons.contains(why.enumCodeValue)
    }

    /// True to go ahead and quit, false to stay running.
    private static func quitRound(_ store: Store, interactive: Bool) async -> Bool {
        guard interactive else {
            _ = await store.unmountAll(force: false, timeout: 10)
            return true
        }
        var force = false
        while true {
            guard let stuck = await unmountWithProgress(store, force: force) else { return false }
            if stuck.isEmpty || force { return true }   // a force is best effort: quit either way
            switch StuckShares.ask(stuck, detail: nil, keep: "Keep Mounted", cancel: true) {
            case .tryAgain: continue
            case .force: force = true
            case .keep: return true
            case .cancel: return false
            }
        }
    }

    /// One unmount round with something on screen: if it hasn't settled within a moment, an
    /// "Unmounting…" alert with a Cancel button goes up, and the round takes it down when it
    /// finishes. Returns the names still mounted, or nil when the user cancelled (the capped
    /// round keeps running to its end in the background; its shares stay busy until then).
    private static func unmountWithProgress(_ store: Store, force: Bool) async -> [String]? {
        final class State { var stuck: [String]?; var modalUp = false }   // main actor only
        let state = State()
        Task { @MainActor in
            state.stuck = await store.unmountAll(force: force)
            // abortModal, not stopModal: this runs from a run loop callback, not a button.
            if state.modalUp { NSApp.abortModal() }
        }
        try? await Task.sleep(for: .milliseconds(800))   // a quick unmount shouldn't flash a dialog
        if let stuck = state.stuck { return stuck }
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = force ? "Force-unmounting shares…" : "Unmounting shares…"
        alert.informativeText = "This can take a moment when a file is in use or a server isn't answering."
        let spinner = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        spinner.style = .spinning
        spinner.startAnimation(nil)
        alert.accessoryView = spinner
        alert.addButton(withTitle: "Cancel")
        state.modalUp = true
        let response = await runModal(alert)
        state.modalUp = false
        return response == .abort ? state.stuck : nil
    }

    /// Runs the alert from a run-loop block rather than from this task's own main-queue job:
    /// a modal loop entered from inside a main-queue block doesn't drain the main queue, so
    /// every main-actor task would stall — including the unmount round that has to end this
    /// very alert. Modes: the normal loop, and the modal-panel one AppKit uses while a
    /// `.terminateLater` reply is pending.
    private static func runModal(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { cont in
            RunLoop.main.perform(inModes: [.common, .modalPanel]) {
                cont.resume(returning: alert.runModal())
            }
        }
    }

    @objc func showPreferences() { WindowManager.shared.showPreferences() }

    #if RELEASE
    /// Creating the controller starts the updater: it schedules automatic checks
    /// (24 h, tunable in Sparkle's own settings UI) and installs what "Check for
    /// Updates…" finds. Only exists in Developer ID release builds — an ad-hoc
    /// signed host can't pass Sparkle's validation of downloaded updates.
    private let updater = SPUStandardUpdaterController(startingUpdater: true,
                                                       updaterDelegate: nil, userDriverDelegate: nil)

    @objc func checkForUpdates() { updater.updater.checkForUpdates() }
    #endif
}

struct MenuContent: View {
    @ObservedObject var store: Store

    var body: some View {
        if store.shares.isEmpty {
            Text("No shares configured")
        } else {
            // A checkmark means mounted; click to toggle.
            ForEach(store.shares) { share in
                let working = store.busy.contains(share.name)
                Toggle(working ? "\(share.name) — working…" : share.name,
                       isOn: Binding(get: { share.mounted },
                                     set: { _ in Task { await store.toggle(share) } }))
                    .disabled(working)
            }
            // Opens a share's mount folder; like Manage Shares' folder button, only once mounted.
            Menu("Show in Finder") {
                ForEach(store.shares) { share in
                    Button(share.name) { Task { await store.reveal(share) } }
                        .disabled(!share.mounted)
                }
            }
        }
        Divider()
        Button("Manage Shares…") { WindowManager.shared.showManage() }
        Button("Preferences…") { WindowManager.shared.showPreferences() }
            .keyboardShortcut(",")
        #if RELEASE
        Button("Check for Updates…") { (NSApp.delegate as? AppDelegate)?.checkForUpdates() }
        #endif
        Divider()
        Button("Quit Mountie") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

@main
struct MountieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            // externaldrive is a wide, low shape that looks undersized next to other menu bar
            // icons at the default font, so the symbol is sized up to a typical bar height.
            Image(systemName: store.shares.contains { $0.mounted }
                  ? "externaldrive.badge.checkmark" : "externaldrive.connected.to.line.below")
                .font(.system(size: 16))
        }
        .menuBarExtraStyle(.menu)
    }
}
