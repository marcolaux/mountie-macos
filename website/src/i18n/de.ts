/**
 * Deutsch — gegen `en` getypt: ein fehlender Schlüssel ist ein Type-Error,
 * kein englisches Wort auf der deutschen Seite.
 */
import type en from "./en";

const de: typeof en = {
  lang: { label: "Sprache" },
  nav: {
    label: "Abschnitte",
    skip: "Zum Inhalt springen",
    why: "Warum",
    shares: "Freigaben",
    automatic: "Automatisch",
    s3: "S3",
    source: "GitHub",
    download: "Laden"
  },
  hero: {
    title: "Freigaben, die sich selbst einhängen.",
    lede: "Mountie beobachtet das Netz — dein heimisches WLAN, dein Tailnet — und hängt jede Freigabe ein, sobald ihr Server antwortet. Gehst du fort, lässt Mountie sie wieder los. NFS, SMB, WebDAV und S3, kein sudo, kein Admin-Passwort.",
    ctaMac: "Für macOS laden",
    ctaSource: "Auf GitHub ansehen",
    hint: "Eingehängte Freigaben in Grün; die wartenden sagen, worauf sie warten."
  },
  why: {
    eyebrow: "Warum",
    title: "Die ganze Idee in drei Teilen.",
    noadmin: {
      title: "Kein Admin-Passwort",
      body: "Mountie hängt über NetFS ein — dieselbe API, die der Finder benutzt. Alles läuft als du: kein sudo, kein Hilfsprogramm, nichts systemweit installiert."
    },
    finder: {
      title: "Finder-nativ",
      body: "Eine eingehängte Freigabe erscheint in der Seitenleiste des Finders, benannt nach der Freigabe, und verschwindet beim Aushängen wieder. Freigaben landen in einem Ordner deiner Wahl — standardmäßig ~/Mountie — und ein manuelles Einhängen öffnet genau dort."
    },
    quit: {
      title: "Geht, wenn du gehst",
      body: "Beim Beenden hängt Mountie alles aus, was es eingehängt hat — nie stillschweigend erzwungen, und jeder Versuch ist auf 15 Sekunden begrenzt, damit ein toter Server das Beenden nicht aufhängt."
    }
  },
  feat: { details: "Im Detail" },
  shares: {
    eyebrow: "Freigaben",
    title: "Wenn du selbst entscheiden willst.",
    body: "Den Alltag erledigt der Automatismus; der Rest ist ein Klick. In der Menüleiste ist jede Freigabe ein Schalter — ein Häkchen heißt eingehängt. Das Fenster hält dieselben Freigaben mit allen Aktionen in der Pille der Zeile.",
    p1: "Das Menüleisten-Symbol trägt ein Häkchen, solange irgendetwas eingehängt ist.",
    p2: "Ein manuelles Einhängen öffnet die Freigabe im Finder; Bearbeiten oder Entfernen einer eingehängten Freigabe bittet erst ums Aushängen.",
    p3: "Beim Beenden hängt Mountie alles aus, was es eingehängt hat. Eine Freigabe, die nicht loslässt, bietet Erneut versuchen, Aushängen erzwingen oder Eingehängt lassen — nie wird stillschweigend erzwungen ausgehängt.",
    p4: "Jeder Aushänge-Versuch ist auf 15 Sekunden begrenzt, damit ein toter Server das Beenden nicht aufhängt.",
    alt: "Das Mountie-Fenster mit vier Freigaben: zwei eingehängt, eine wartet auf Tailscale, eine auf WLAN"
  },
  protocols: {
    eyebrow: "Protokolle",
    title: "NFS, SMB, WebDAV — und S3.",
    body: "Jede Adresse ist eine URL, und die Freigaben liegen in einer Textdatei, die du auch von Hand bearbeiten kannst. Passwörter werden nie aufgeschrieben: SMB und WebDAV melden sich über den eigenen Dialog von macOS an und können im Schlüsselbund gespeichert werden.",
    p1: "NFS: Server und Pfad, Mount-Optionen wenn gewünscht — standardmäßig soft.",
    p2: "SMB: Server und Freigabe, optional ein Benutzername, und beim ersten Mal der Anmeldedialog von macOS.",
    p3: "WebDAV: Server und Pfad, HTTPS standardmäßig an.",
    p4: "Nicht dabei: AFP, dessen Client es in macOS nicht mehr gibt, und SFTP/FTP, für die es keinen brauchbaren eingebauten Client gibt.",
    alt: "Der Freigaben-Tab des Editors mit Feldern für Protokoll, Name, Server und Pfad"
  },
  automatic: {
    eyebrow: "Automatisch",
    title: "Es weiß, wo du bist.",
    body: "Das automatische Einhängen beobachtet den Port des Servers — 2049 für NFS, 445 für SMB, sonst den Port in der Adresse. Erreichbar, und die Freigabe hängt ein; zwei verpasste Prüfungen in Folge, und sie hängt aus. Du bestimmst, wo das gilt.",
    p1: "Die Bedingungen gelten pro Freigabe und kennen den Kontext: nur in WLANs, denen dieser Mac schon beigetreten ist, nur bei laufendem Tailscale — sogar beschränkt auf ein bestimmtes Tailnet — und bei beidem genügt eines. Das NAS bleibt zu Hause; der Arbeits-Bucket folgt dir überallhin.",
    p2: "WLAN-Regeln brauchen den Namen des Netzwerks, den macOS nur Apps mit Ortungsfreigabe verrät. Sie wird beim ersten Öffnen des Tabs Automatisch erfragt — nie beim Start — und für nichts anderes benutzt.",
    p3: "Es reagiert auf Änderungen: hängst du eine automatische Freigabe von Hand aus, bleibt sie ausgehängt, bis der Server weg und wieder da war.",
    p4: "Geprüft wird alle 10 Sekunden und sofort nach einem Netzwerkwechsel oder Aufwachen.",
    alt: "Der Tab Automatisch des Editors mit den Bedingungen für Tailscale und WLAN"
  },
  s3: {
    eyebrow: "S3",
    title: "Ein Bucket, eingehängt wie eine Freigabe.",
    body: "macOS hat kein eingebautes S3-Dateisystem, also bringt Mountie rclone mit, das den Bucket als NFS auf 127.0.0.1 bereitstellt — kein FUSE, kein sudo. rclone startet mit dem Einhängen und endet mit dem Aushängen; nichts anderes benutzt es je.",
    p1: "Zugangsschlüssel werden im Editor der Freigabe eingegeben, im Schlüsselbund aufbewahrt — nie in der Konfigurationsdatei oder auf der Platte — und nur beim Einhängen oder Prüfen an rclone übergeben.",
    p2: "Ein Endpunkt mit host:port funktioniert für Minio, Wasabi und andere S3-kompatible Dienste, mit einem HTTPS-Schalter für unverschlüsselte Endpunkte.",
    p3: "Das automatische Einhängen zählt einen Bucket nur als erreichbar, wenn rclone ihn wirklich auflisten kann — falsche Schlüssel gelten als Server nicht verfügbar.",
    codeNote: "Die Konfigurationsdatei, unter ~/Library/Application Support/Mountie/shares.conf. Schlüssel stehen nie darin."
  },
  more: {
    eyebrow: "Und",
    title: "Der Rest dessen, was es tut.",
    menubar: { title: "Menüleiste", body: "Jede Freigabe ist ein Menüeintrag mit Häkchen, wenn eingehängt. Freigaben verwalten… und Einstellungen… leben dort auch." },
    sidebar: { title: "Finder-Seitenleiste", body: "Eingehängte Freigaben gesellen sich automatisch in die Seitenleiste, benannt nach der Freigabe. Favoriten, die du selbst hinzogst, werden nie angefasst." },
    quitUnmount: { title: "Beenden hängt aus", body: "Beim Beenden hängt Mountie alles aus, was es eingehängt hat — standardmäßig an, in den Einstellungen aus, wenn Freigaben bleiben sollen." },
    keychain: { title: "Passwörter im Schlüsselbund", body: "Die App sieht oder speichert nie ein SMB- oder WebDAV-Passwort, und S3-Schlüssel liegen ebenfalls direkt im Schlüsselbund." },
    cli: { title: "Ein CLI", body: "mountiectl listet, hängt ein und aus und prüft Freigaben — für Skripte, SSH-Sitzungen und wählerische Morgen." },
    prefs: { title: "Einstellungen", body: "Beim Anmelden starten, das Fenster beim Start verstecken und den Ordner wählen, in den Freigaben eingehängt werden." }
  },
  status: {
    eyebrow: "Wo die Dinge stehen",
    title: "Signiert, und ehrlich zum Rest.",
    body: "Mountie ist mit einem Developer-ID-Zertifikat signiert, aber die Releases sind noch nicht notarisiert — der erste Start fragt deshalb eventuell nach einer Bestätigung. Es läuft ab macOS 14, auf Apple Silicon wie auf Intel. Auf der Serverseite müssen NFS-Exports nicht-reservierte Client-Ports erlauben (insecure unter Linux), weil unprivilegierte Mounts keine Ports unter 1024 benutzen können.",
    readme: "Lies das README",
    releases: "Alle Releases"
  },
  download: {
    eyebrow: "Laden",
    title: "Probefahrt gefällig?",
    lede: "Ein Zip, ein Ziehen nach ~/Applications. Kein Installer, kein Konto.",
    mac: "macOS · universal",
    macNote: "macOS 14 oder neuer",
    version: "Version {v}, gebaut {d}",
    releases: "Alle Releases",
    readFirst: "Lies das README"
  },
  footer: {
    label: "Fußzeile",
    releases: "Releases",
    readme: "README",
    source: "Quelltext",
    contact: "Kontakt",
    made: "© {year} Marco Laux",
    by: "präsentiert von"
  },
  shot: { pending: "Screenshot folgt" }
};

export default de;
