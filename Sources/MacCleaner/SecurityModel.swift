import Foundation
import SwiftUI

enum Level: Int, Comparable {
    case ok, info, warn, danger
    static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }

    var color: Color {
        switch self {
        case .ok: .green
        case .info: .blue
        case .warn: .orange
        case .danger: .red
        }
    }

    var symbol: String {
        switch self {
        case .ok: "checkmark.circle.fill"
        case .info: "info.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .danger: "xmark.octagon.fill"
        }
    }
}

struct SecCheck: Identifiable {
    let title: String
    let detail: String
    let level: Level
    var pane: String? = nil
    var id: String { title }
}

struct AutostartItem: Identifiable {
    let plist: URL
    let label: String
    let program: String?
    let level: Level
    let note: String
    let scope: String
    var id: String { plist.path }
}

struct ProcFinding: Identifiable {
    let path: String
    let note: String
    let level: Level
    var id: String { path }
}

enum SecurityScanner {
    static let launchDirs: [(String, String)] = [
        (home.path + "/Library/LaunchAgents", "Benutzer"),
        ("/Library/LaunchAgents", "Alle Benutzer"),
        ("/Library/LaunchDaemons", "Systemdienst"),
    ]

    static func plistPaths() -> Set<String> {
        var s = Set<String>()
        for (dir, _) in launchDirs {
            for u in FS.children(dir) ?? [] where u.pathExtension == "plist" { s.insert(u.path) }
        }
        return s
    }

    // MARK: Signatures

    struct Sig {
        let signed: Bool
        let valid: Bool
        let adhoc: Bool
        let signer: String
    }

    static func signature(_ path: String) async -> Sig {
        let info = await Shell.sh("codesign -dv --verbose=2 \(Shell.quote(path)) 2>&1")
        if info.contains("not signed at all") || info.contains("code object is not signed") {
            return Sig(signed: false, valid: false, adhoc: false, signer: "nicht signiert")
        }
        let lines = info.split(separator: "\n").map(String.init)
        var signer = lines.first { $0.hasPrefix("Authority=") }.map { String($0.dropFirst("Authority=".count)) }
        let adhoc = signer == nil && info.contains("Signature=adhoc")
        let valid = await Shell.run("/usr/bin/codesign", ["--verify", path]).code == 0
        signer = signer?.replacingOccurrences(of: "Developer ID Application: ", with: "")
        if signer == "Software Signing" { signer = "Apple" }
        if signer?.hasPrefix("Apple Mac OS Application Signing") == true { signer = "App Store" }
        return Sig(signed: true, valid: valid, adhoc: adhoc, signer: signer ?? (adhoc ? "ad-hoc signiert" : "signiert"))
    }

    static func suspiciousLocation(_ p: String) -> Bool {
        let bad = ["/tmp/", "/private/tmp/", "/var/tmp/", "/private/var/tmp/", "/Users/Shared/", "/private/var/folders/"]
        if bad.contains(where: { p.hasPrefix($0) }) { return true }
        return p.split(separator: "/").contains { $0.hasPrefix(".") }
    }

    // MARK: Autostart

    static func scanAutostart() async -> [AutostartItem] {
        var result: [AutostartItem] = []
        for (dir, scope) in launchDirs {
            for url in FS.children(dir) ?? [] where url.pathExtension == "plist" {
                let data = try? Data(contentsOf: url.resolvingSymlinksInPath())
                let dict = data.flatMap {
                    try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any]
                } ?? [:]
                let label = dict["Label"] as? String ?? url.deletingPathExtension().lastPathComponent
                let args = dict["ProgramArguments"] as? [String] ?? []
                var program = (dict["Program"] as? String) ?? args.first
                if program == "/usr/bin/open", let app = args.first(where: { $0.hasSuffix(".app") }) {
                    program = app
                }
                result.append(await evaluate(url, label, program, scope, isEmpty: dict.isEmpty))
            }
        }
        return result.sorted { $0.level != $1.level ? $0.level > $1.level : $0.label < $1.label }
    }

    private static func evaluate(_ plist: URL, _ label: String, _ program: String?, _ scope: String,
                                 isEmpty: Bool) async -> AutostartItem {
        func item(_ level: Level, _ note: String) -> AutostartItem {
            AutostartItem(plist: plist, label: label, program: program, level: level, note: note, scope: scope)
        }
        guard let program else {
            return item(.ok, isEmpty ? "Leerer Platzhalter – startet nichts" : "Kein Programm angegeben")
        }
        guard FileManager.default.fileExists(atPath: program) else {
            return item(.info, "Programm fehlt – verwaister Eintrag, kann weg")
        }
        let sig = await signature(program)
        if suspiciousLocation(program) {
            return item(.danger, "Startet aus einem ungewöhnlichen Ordner – typisch für Schadsoftware (\(sig.signer))")
        }
        if !sig.signed { return item(.warn, "Nicht signiert – Herkunft unklar") }
        if !sig.valid { return item(.warn, "Signatur ungültig – Programm wurde verändert (\(sig.signer))") }
        if sig.adhoc { return item(.info, "Ohne Herstellerzertifikat (z. B. MacPorts/Homebrew)") }
        return item(.ok, sig.signer)
    }

    // MARK: Running processes

    static func scanProcesses() async -> [ProcFinding] {
        let out = await Shell.run("/bin/ps", ["-axo", "comm="]).out
        let skip = ["/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/sbin/", "/bin/", "/Library/Apple/"]
        let own = Bundle.main.executablePath ?? ""
        let paths = Set(out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) })
            .filter { $0.hasPrefix("/") && !skip.contains(where: $0.hasPrefix) && $0 != own }
            .filter { FileManager.default.fileExists(atPath: $0) }

        var result: [ProcFinding] = []
        for p in paths.sorted() {
            let sig = await signature(p)
            let iosApp = p.contains("/Wrapper/")
            let translocated = p.contains("/AppTranslocation/")
            if translocated {
                result.append(ProcFinding(path: p, note: "Läuft aus einer Quarantäne-Kopie – App wurde nicht in „Programme“ verschoben", level: .info))
            } else if suspiciousLocation(p) && !iosApp {
                result.append(ProcFinding(path: p, note: "Läuft aus einem ungewöhnlichen Ordner (\(sig.signer))",
                                          level: sig.signed && sig.valid && !sig.adhoc ? .warn : .danger))
            } else if !sig.signed {
                result.append(ProcFinding(path: p, note: "Nicht signiert – Herkunft unklar", level: .warn))
            } else if !sig.valid && !iosApp {
                result.append(ProcFinding(path: p, note: "Signatur ungültig – Programm wurde verändert (\(sig.signer))", level: .warn))
            } else if sig.adhoc {
                result.append(ProcFinding(path: p, note: "Ohne Herstellerzertifikat (z. B. selbst gebaut, MacPorts/Homebrew)", level: .info))
            }
        }
        return result.sorted { $0.level != $1.level ? $0.level > $1.level : $0.path < $1.path }
    }

    // MARK: System checks

    static func runChecks() async -> [SecCheck] {
        var r: [SecCheck] = []

        let sip = await Shell.sh("csrutil status")
        r.append(sip.contains("enabled")
            ? SecCheck(title: "Systemintegritätsschutz (SIP)", detail: "Aktiv – Systemdateien sind geschützt.", level: .ok)
            : SecCheck(title: "Systemintegritätsschutz (SIP)", detail: "Ausgeschaltet! Systemdateien können verändert werden.", level: .danger))

        let gk = await Shell.sh("spctl --status 2>&1")
        r.append(gk.contains("enabled")
            ? SecCheck(title: "Gatekeeper", detail: "Aktiv – nur geprüfte Programme starten ohne Rückfrage.", level: .ok)
            : SecCheck(title: "Gatekeeper", detail: "Ausgeschaltet – Programme werden beim Start nicht geprüft.", level: .warn))

        let fv = await Shell.sh("fdesetup status")
        r.append(fv.contains("On")
            ? SecCheck(title: "FileVault", detail: "Aktiv – die Festplatte ist verschlüsselt.", level: .ok)
            : SecCheck(title: "FileVault", detail: "Aus – bei Diebstahl sind deine Daten lesbar.", level: .warn,
                       pane: "x-apple.systempreferences:com.apple.preference.security?FileVault"))

        let fw = await Shell.sh("/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate")
        r.append(fw.contains("enabled")
            ? SecCheck(title: "Firewall", detail: "Aktiv.", level: .ok)
            : SecCheck(title: "Firewall", detail: "Ausgeschaltet – eingehende Verbindungen werden nicht gefiltert.",
                       level: .warn, pane: SettingsPane.firewall))

        let services: [(Int, String)] = [
            (22, "Entfernte Anmeldung (SSH)"), (5900, "Bildschirmfreigabe"),
            (3283, "Entfernte Verwaltung (Remote Desktop)"), (445, "Dateifreigabe (SMB)"),
        ]
        for (port, name) in services {
            let open = await Shell.run("/usr/bin/nc", ["-z", "-G", "1", "127.0.0.1", "\(port)"]).code == 0
            r.append(open
                ? SecCheck(title: name, detail: "Eingeschaltet – andere Geräte können sich verbinden (Port \(port)). Ausschalten, wenn du es nicht brauchst.",
                           level: .warn, pane: SettingsPane.sharing)
                : SecCheck(title: name, detail: "Aus.", level: .ok))
        }

        let profiles = await Shell.sh("profiles list 2>&1")
        let mdm = await Shell.sh("profiles status -type enrollment 2>&1")
        r.append(profiles.contains("no configuration profiles") && !mdm.contains("MDM enrollment: Yes")
            ? SecCheck(title: "Profile & Fernverwaltung", detail: "Keine Profile installiert, keine Fernverwaltung (MDM).", level: .ok)
            : SecCheck(title: "Profile & Fernverwaltung", detail: "Es sind Profile installiert oder der Mac wird fernverwaltet. Prüfe, ob du das kennst.",
                       level: .warn, pane: SettingsPane.profiles))

        let hosts = (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8)) ?? ""
        var extra: [String] = []
        for raw in hosts.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasSuffix("localhost") || line.hasSuffix("broadcasthost") { continue }
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            if let host = fields.last { extra.append(String(host)) }
        }
        r.append(extra.isEmpty
            ? SecCheck(title: "Hosts-Datei", detail: "Unverändert.", level: .ok)
            : SecCheck(title: "Hosts-Datei", detail: "\(extra.count) zusätzliche Einträge, z. B. \(extra.prefix(3).joined(separator: ", ")). Solche Sperren stammen oft von gecrackter Software.", level: .warn))

        let proxy = await Shell.sh("scutil --proxy")
        let proxyOn = ["HTTPEnable : 1", "HTTPSEnable : 1", "ProxyAutoConfigEnable : 1", "SOCKSEnable : 1"].contains { proxy.contains($0) }
        r.append(proxyOn
            ? SecCheck(title: "Proxy", detail: "Ein Proxy ist eingestellt – dein Internetverkehr läuft über einen anderen Rechner. Prüfe, ob du das eingerichtet hast.", level: .warn)
            : SecCheck(title: "Proxy", detail: "Kein Proxy eingestellt.", level: .ok))

        let kexts = await Shell.sh("kmutil showloaded --list-only 2>/dev/null | awk '{print $6}' | grep -v '^com.apple' | grep '\\.'")
        let kextList = kexts.split(separator: "\n").map(String.init)
        if !kextList.isEmpty {
            r.append(SecCheck(title: "Fremde Kernel-Erweiterungen", detail: kextList.joined(separator: ", "), level: .info))
        }
        let sysext = await Shell.sh("systemextensionsctl list 2>/dev/null | grep 'activated enabled' | awk '{print $4}'")
        let sysextList = sysext.split(separator: "\n").map(String.init)
        if !sysextList.isEmpty {
            r.append(SecCheck(title: "Systemerweiterungen", detail: sysextList.joined(separator: ", "), level: .info))
        }

        let listen = await Shell.sh("lsof -nP -iTCP -sTCP:LISTEN 2>/dev/null | awk 'NR>1 {print $1\" \"$9}' | sort -u")
        let external = listen.split(separator: "\n").map(String.init)
            .filter { !$0.contains("127.0.0.1:") && !$0.contains("[::1]:") }
        if !external.isEmpty {
            r.append(SecCheck(title: "Programme, die auf Verbindungen warten",
                              detail: external.map { $0.replacingOccurrences(of: "\\x20", with: " ") }.joined(separator: " · "),
                              level: .info))
        }

        r.append(SecCheck(title: "Bildschirmaufnahme – selbst prüfen", detail: "Welche Apps dürfen deinen Bildschirm sehen? Unbekannte Einträge sind das wichtigste Warnzeichen.", level: .info, pane: SettingsPane.screenCapture))
        r.append(SecCheck(title: "Bedienungshilfen – selbst prüfen", detail: "Apps hier können deinen Mac fernsteuern.", level: .info, pane: SettingsPane.accessibility))
        r.append(SecCheck(title: "Eingabeüberwachung – selbst prüfen", detail: "Apps hier können Tastatureingaben mitlesen.", level: .info, pane: SettingsPane.inputMonitoring))
        r.append(SecCheck(title: "Mikrofon & Kamera – selbst prüfen", detail: "Welche Apps dürfen zuhören oder filmen?", level: .info, pane: SettingsPane.microphone))
        return r
    }
}

@MainActor
final class SecurityModel: ObservableObject {
    static let shared = SecurityModel()

    @Published var checks: [SecCheck] = []
    @Published var autostart: [AutostartItem] = []
    @Published var processes: [ProcFinding] = []
    @Published var scanning = false
    @Published var lastScan: Date?
    @Published var newItems: [String] = []
    @Published var message: String?

    private let knownKey = "knownAutostart"
    private var notified = Set<String>()
    private var timer: Timer?

    var findings: [Level] { checks.map(\.level) + autostart.map(\.level) + processes.map(\.level) }
    var issueCount: Int { findings.filter { $0 >= .warn }.count }
    var worst: Level { findings.max() ?? .ok }

    var statusText: String {
        if scanning && lastScan == nil { return "wird geprüft…" }
        if lastScan == nil { return "noch nicht geprüft" }
        return issueCount == 0 ? "alles in Ordnung" : "\(issueCount) Hinweise"
    }

    func scan() async {
        guard !scanning else { return }
        scanning = true
        async let c = SecurityScanner.runChecks()
        async let a = SecurityScanner.scanAutostart()
        async let p = SecurityScanner.scanProcesses()
        checks = await c
        autostart = await a
        processes = await p
        compareWithKnown()
        lastScan = Date()
        scanning = false
    }

    private func compareWithKnown() {
        let current = Set(autostart.map(\.id))
        if let known = UserDefaults.standard.stringArray(forKey: knownKey) {
            newItems = current.subtracting(known).sorted()
        } else {
            UserDefaults.standard.set(Array(current), forKey: knownKey)
        }
    }

    func acceptNew() {
        var known = Set(UserDefaults.standard.stringArray(forKey: knownKey) ?? [])
        known.formUnion(newItems)
        UserDefaults.standard.set(Array(known), forKey: knownKey)
        newItems = []
    }

    func remove(_ item: AutostartItem) async {
        message = await Remover.moveToTrash([item.plist])
            ?? "„\(item.label)“ wurde deaktiviert und liegt im Papierkorb."
        await scan()
    }

    // MARK: Background monitoring

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task { @MainActor in await SecurityModel.shared.quickCheck() }
        }
        Task { await quickCheck() }
    }

    func quickCheck() async {
        let enabled = UserDefaults.standard.object(forKey: "monitor") as? Bool ?? true
        guard enabled, !scanning else { return }
        guard let known = UserDefaults.standard.stringArray(forKey: knownKey) else {
            await scan()   // first start: learn what is there
            return
        }
        let current = SecurityScanner.plistPaths()
        let unknown = current.subtracting(known)
        newItems = unknown.sorted()
        let fresh = unknown.subtracting(notified)
        if !fresh.isEmpty {
            notified.formUnion(fresh)
            let names = fresh.map { URL(fileURLWithPath: $0).lastPathComponent }.joined(separator: ", ")
            Notify.post("Neuer Autostart-Eintrag", "\(names) – bitte in MacCleaner prüfen.")
        }
    }
}
