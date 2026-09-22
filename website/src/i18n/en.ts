/**
 * English — the shape every other catalog is typed against.
 *
 * Voice: descriptive, third person, the README's tone. Sentences are short
 * and they say what the thing does, not what it promises.
 *
 * vue-i18n syntax: `{name}` is a parameter, `{'@'}` is a literal at-sign
 * (a bare `@` starts a linked message), `|` would split plurals. Keep those
 * three out of prose unless they are meant.
 */
const en = {
  lang: { label: "Language" },
  nav: {
    label: "Sections",
    skip: "Skip to content",
    why: "Why",
    shares: "Shares",
    automatic: "Automatic",
    s3: "S3",
    source: "GitHub",
    download: "Download"
  },
  hero: {
    title: "Shares that mount themselves.",
    lede: "Mountie watches the network — your home Wi-Fi, your tailnet — and mounts each share the moment its server answers. Walk away, and it lets go. NFS, SMB, WebDAV and S3, no sudo, no admin password.",
    ctaMac: "Download for macOS",
    ctaSource: "View on GitHub",
    hint: "Mounted shares in green; the ones waiting say what they're waiting for."
  },
  why: {
    eyebrow: "Why",
    title: "The whole idea, in three parts.",
    noadmin: {
      title: "No admin password",
      body: "Mountie mounts through NetFS — the same API Finder uses. Everything runs as you: no sudo, no helper tool, nothing installed system-wide."
    },
    finder: {
      title: "Finder-native",
      body: "A mounted share appears in Finder's sidebar, named after the share, and disappears again on unmount. Shares land in a folder you pick — ~/Mountie by default — and a manual mount opens right there."
    },
    quit: {
      title: "Leaves when you do",
      body: "Quitting unmounts everything Mountie mounted — never force-unmounted silently, and every attempt is capped at 15 seconds so a dead server can't hang the quit."
    }
  },
  feat: { details: "In detail" },
  shares: {
    eyebrow: "Shares",
    title: "When you want to decide.",
    body: "Automatic handles the routine; the rest is one click. From the menu bar, each share is a toggle — a checkmark means mounted. The window holds the same shares with every action on the row's pill.",
    p1: "The menu bar icon wears a checkmark badge while anything is mounted.",
    p2: "A manual mount opens the share in Finder; editing or removing a mounted share is asked to unmount first.",
    p3: "Quitting unmounts everything Mountie mounted. A share that won't let go offers Try Again, Force Unmount or Keep Mounted — nothing is ever force-unmounted silently.",
    p4: "Each unmount attempt is capped at 15 seconds, so a dead server can't hang the quit.",
    alt: "The Mountie window listing four shares: two mounted, one waiting for Tailscale, one waiting for Wi-Fi"
  },
  protocols: {
    eyebrow: "Protocols",
    title: "NFS, SMB, WebDAV — and S3.",
    body: "Every address is a URL, and shares live in a plain-text file you can also edit by hand. Passwords are never written down: SMB and WebDAV sign in through macOS's own dialog and can save to the Keychain.",
    p1: "NFS: server and path, mount options if you want them — soft by default.",
    p2: "SMB: server and share, an optional username, and macOS's sign-in dialog the first time.",
    p3: "WebDAV: server and path, HTTPS on by default.",
    p4: "Not offered: AFP, whose client no longer exists in macOS, and SFTP/FTP, which have no usable built-in client.",
    alt: "The share editor's Share tab, with protocol, name, server and path fields"
  },
  automatic: {
    eyebrow: "Automatic",
    title: "It knows where you are.",
    body: "Automatic mounting watches the server's port — 2049 for NFS, 445 for SMB, the port in the address otherwise. Reachable, and the share mounts; two missed checks in a row, and it's unmounted. You decide where that applies.",
    p1: "Conditions are per share and context-aware: only on Wi-Fi networks this Mac has already joined, only when Tailscale is running — even restricted to one chosen tailnet — and with both set, either is enough. The NAS stays home; the work bucket follows you anywhere.",
    p2: "Wi-Fi rules need the network's name, which macOS only reveals to apps with Location access. It's asked for the first time you open the Automatic tab — never at launch — and used for nothing else.",
    p3: "It reacts to changes: unmount an automatic share by hand and it stays unmounted until the server goes away and comes back.",
    p4: "Checks run every 10 seconds, and immediately after a network change or a wake from sleep.",
    alt: "The share editor's Automatic tab, with the Tailscale and Wi-Fi conditions"
  },
  s3: {
    eyebrow: "S3",
    title: "A bucket, mounted like a share.",
    body: "macOS has no built-in S3 file system, so Mountie bundles rclone, which serves the bucket as NFS on 127.0.0.1 — no FUSE and no sudo. rclone starts when the share mounts and stops when it unmounts; nothing else ever involves it.",
    p1: "Access keys are entered in the share editor, kept in the Keychain — never in the config file or on disk — and handed to rclone only when mounting or probing.",
    p2: "A host:port endpoint works for Minio, Wasabi and other S3-compatible services, with an HTTPS toggle for endpoints that aren't encrypted.",
    p3: "Automatic mounting counts a bucket as reachable only when rclone can actually list it, so wrong keys read as server unavailable.",
    codeNote: "The config file, at ~/Library/Application Support/Mountie/shares.conf. Keys are never in it."
  },
  more: {
    eyebrow: "And",
    title: "The rest of what it does.",
    menubar: { title: "Menu bar", body: "Each share is a menu item with a checkmark when mounted. Manage Shares… and Preferences… live there too." },
    sidebar: { title: "Finder sidebar", body: "Mounted shares join the sidebar automatically, named after the share. Favorites you dragged there yourself are never touched." },
    quitUnmount: { title: "Quit unmounts", body: "Quitting unmounts everything Mountie mounted — on by default, off in Preferences if shares should stay." },
    keychain: { title: "Passwords in the Keychain", body: "The app never sees or stores an SMB or WebDAV password, and S3 keys live in the Keychain directly." },
    cli: { title: "A CLI", body: "mountiectl lists, mounts, unmounts and probes shares — for scripts, SSH sessions and picky mornings." },
    prefs: { title: "Preferences", body: "Start at login, hide the window on start, and choose the folder shares mount into." }
  },
  status: {
    eyebrow: "Where things stand",
    title: "Signed, and honest about the rest.",
    body: "Mountie is signed with a Developer ID certificate, but releases aren't notarized yet, so the first launch may ask you to confirm. It runs on macOS 14 or newer, on Apple silicon and Intel alike. On the server side, NFS exports must allow non-reserved client ports (insecure on Linux), because unprivileged mounts can't use ports below 1024.",
    readme: "Read the README",
    releases: "All releases"
  },
  download: {
    eyebrow: "Download",
    title: "Take it for a drive.",
    lede: "One zip, one drag into ~/Applications. No installer, no account.",
    mac: "macOS · universal",
    macNote: "macOS 14 or newer",
    version: "Version {v}, built {d}",
    releases: "All releases",
    readFirst: "Read the README"
  },
  footer: {
    label: "Footer",
    releases: "Releases",
    readme: "README",
    source: "Source",
    contact: "Contact",
    made: "© {year} Marco Laux",
    by: "brought to you by"
  },
  shot: { pending: "Screenshot pending" }
};

export default en;
