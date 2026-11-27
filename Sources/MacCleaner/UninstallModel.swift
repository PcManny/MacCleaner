import AppKit
import Foundation

struct AppEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let bundleID: String?
    var id: String { url.path }
}

struct Leftover: Identifiable {
    let url: URL
    var size: Int64
    let note: String
    var selected: Bool
    var id: String { url.path }
}

enum AppScanner {
    static func findApps() -> [AppEntry] {
        var result: [AppEntry] = []
        func scan(_ dir: String, depth: Int) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
            for n in names {
                let p = dir + "/" + n
                if n.hasSuffix(".app") {
                    let bid = Bundle(path: p)?.bundleIdentifier
                    if bid?.hasPrefix("com.apple.") == true { continue }
                    result.append(AppEntry(url: URL(fileURLWithPath: p), name: String(n.dropLast(4)), bundleID: bid))
                } else if depth > 0, FS.isDirectory(p) {
                    scan(p, depth: depth - 1)
                }
            }
        }
        scan("/Applications", depth: 1)
        scan(home.path + "/Applications", depth: 1)
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static let userLibrary = [
        "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Containers", "Group Containers",
        "Saved Application State", "LaunchAgents", "Logs", "HTTPStorages", "WebKit", "Cookies", "Application Scripts",
    ].map { home.path + "/Library/" + $0 }

    static let systemLibrary = [
        "/Library/Application Support", "/Library/Caches", "/Library/Preferences", "/Library/LaunchAgents",
        "/Library/LaunchDaemons", "/Library/PrivilegedHelperTools", "/Library/Logs", "/Library/Audio/Plug-Ins/HAL",
    ]

    static func stem(_ name: String) -> String {
        var s = name.lowercased()
        for suffix in [".plist", ".savedstate", ".binarycookies"] where s.hasSuffix(suffix) {
            s.removeLast(suffix.count)
        }
        return s
    }

    /// Files and folders that belong to an app. Vendor matches are only suggested, not preselected.
    static func leftovers(for app: AppEntry) -> [(URL, String, Bool)] {
        let name = app.name.lowercased()
        let compact = name.replacingOccurrences(of: " ", with: "")
        let bid = app.bundleID?.lowercased()
        let parts = bid?.split(separator: ".") ?? []
        let vendor = parts.count >= 3 ? parts.prefix(2).joined(separator: ".") : nil

        // Name variants: "Beispiel_5" also stands for "beispiel 5" and "beispiel5".
        let names = Set([name, compact, name.replacingOccurrences(of: "_", with: " "),
                         name.replacingOccurrences(of: "_", with: ""), name.replacingOccurrences(of: " ", with: "_")])
        let separators = [" ", "_", "-", "."]
        // Same product, other version: com.hersteller.produkt5 → com.hersteller.produkt4.menu
        var family: String?
        if let bid, parts.count >= 3, let last = parts.last {
            let base = String(last.reversed().drop(while: \.isNumber).reversed())
            if base.count >= 4, base.count < last.count { family = parts.dropLast().joined(separator: ".") + "." + base }
        }

        var out: [(URL, String, Bool)] = []
        for dir in userLibrary + systemLibrary {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for n in entries {
                let s = stem(n)
                let u = URL(fileURLWithPath: dir).appendingPathComponent(n)
                if let bid, s == bid || s.hasPrefix(bid + ".") || (parts.count >= 3 && s.contains(bid)) {
                    out.append((u, "gehört zu \(app.name)", true))
                } else if name.count >= 4, names.contains(s) {
                    out.append((u, "trägt den Namen „\(app.name)“", true))
                } else if name.count >= 6, names.contains(where: { v in separators.contains { s.hasPrefix(v + $0) } }) {
                    // Short names ("Claude" → "claude-cli-nodejs") hit other programs: only suggest.
                    let sure = name.count >= 10
                    out.append((u, sure ? "Teil von „\(app.name)“" : "Teil von „\(app.name)“? – bitte prüfen", sure))
                } else if let family, let other = otherVersionID(s, family: family), other != bid {
                    // Preselect only if that other version is not installed any more.
                    let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: other) != nil
                    out.append((u, installed ? "andere Version (\(other)) – ist noch installiert"
                                             : "ältere Version von \(app.name)", !installed))
                } else if let vendor, vendor != "com.apple", s.hasPrefix(vendor + ".") {
                    out.append((u, "gleicher Hersteller (\(vendor)) – nur wählen, wenn nichts anderes von ihm bleibt", false))
                }
            }
        }
        return out
    }

    /// "com.hersteller.produkt4.menu" with family "com.hersteller.produkt" → "com.hersteller.produkt4".
    static func otherVersionID(_ s: String, family: String) -> String? {
        guard s.hasPrefix(family) else { return nil }
        let rest = s.dropFirst(family.count)
        let digits = rest.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        let after = rest.dropFirst(digits.count)
        guard after.isEmpty || after.hasPrefix(".") else { return nil }
        return family + digits
    }

    /// Library entries named like a bundle ID whose app is no longer installed.
    static func orphans(installed: [AppEntry]) -> [(URL, String)] {
        let ids = installed.compactMap { $0.bundleID?.lowercased() }
        let regex = try! NSRegularExpression(pattern: "^[a-z0-9-]+\\.[a-z0-9-]+\\.[a-z0-9._-]+$")
        let dirs = ["Application Support", "Caches", "Preferences", "Containers", "Saved Application State",
                    "HTTPStorages", "WebKit", "Logs"].map { home.path + "/Library/" + $0 }
        var out: [(URL, String)] = []

        for dir in dirs {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for n in names {
                let s = stem(n)
                let range = NSRange(s.startIndex..., in: s)
                guard regex.firstMatch(in: s, range: range) != nil,
                      !s.hasPrefix("com.apple."), !s.hasPrefix("group.com.apple"), !s.hasPrefix("app.maccleaner")
                else { continue }
                if ids.contains(where: { s == $0 || s.hasPrefix($0 + ".") || $0.hasPrefix(s + ".") }) { continue }
                if NSWorkspace.shared.urlForApplication(withBundleIdentifier: s) != nil { continue }
                out.append((URL(fileURLWithPath: dir).appendingPathComponent(n), "Programm „\(s)“ ist nicht mehr installiert"))
            }
        }

        // Autostart entries whose program no longer exists.
        let agents = home.path + "/Library/LaunchAgents"
        for u in FS.children(agents) ?? [] where u.pathExtension == "plist" {
            guard let data = try? Data(contentsOf: u),
                  let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            else { continue }
            let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
            if let program, program.hasPrefix("/"), !FileManager.default.fileExists(atPath: program) {
                out.append((u, "Autostart-Eintrag, dessen Programm fehlt"))
            }
        }
        return out
    }
}

@MainActor
final class UninstallModel: ObservableObject {
    static let shared = UninstallModel()

    @Published var apps: [AppEntry] = []
    @Published var sizes: [String: Int64] = [:]
    @Published var selection: Set<AppEntry.ID> = []
    @Published var leftovers: [Leftover] = []
    @Published var orphans: [Leftover] = []
    @Published var busy = false
    @Published var orphanBusy = false
    @Published var orphansScanned = false
    @Published var message: String?
    @Published var search = ""
    @Published var sortBySize = false

    /// Selected apps in list order.
    var selectedApps: [AppEntry] { apps.filter { selection.contains($0.id) } }
    var selectedApp: AppEntry? { selectedApps.count == 1 ? selectedApps.first : nil }

    var filtered: [AppEntry] {
        let list = search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
        return sortBySize ? list.sorted { (sizes[$0.id] ?? 0) > (sizes[$1.id] ?? 0) } : list
    }

    var uninstallTotal: Int64 {
        selectedApps.reduce(0) { $0 + (sizes[$1.id] ?? 0) } + leftovers.filter(\.selected).reduce(0) { $0 + $1.size }
    }

    var orphanTotal: Int64 { orphans.filter(\.selected).reduce(0) { $0 + $1.size } }

    func loadApps() async {
        let list = await Task.detached { AppScanner.findApps() }.value
        apps = list
        sizes = await DiskUsage.sizes(list.map(\.url.path))
    }

    func select(_ ids: Set<AppEntry.ID>) async {
        selection = ids
        message = nil
        leftovers = []
        let chosen = selectedApps
        guard !chosen.isEmpty else { busy = false; return }
        busy = true
        let found = await Task.detached { () -> [(URL, String, Bool)] in
            var seen = Set<String>()
            var all: [(URL, String, Bool)] = []
            for app in chosen {
                for f in AppScanner.leftovers(for: app) where seen.insert(f.0.path).inserted {
                    // With several apps, say which program each leftover belongs to.
                    all.append(chosen.count > 1 ? (f.0, "\(app.name): \(f.1)", f.2) : f)
                }
            }
            return all
        }.value
        let s = await DiskUsage.sizes(found.map { $0.0.path })
        guard selection == ids else { return }
        leftovers = found.map { Leftover(url: $0.0, size: s[$0.0.path] ?? 0, note: $0.1, selected: $0.2) }
            .sorted { $0.selected != $1.selected ? $0.selected : $0.size > $1.size }
        busy = false
    }

    func toggle(_ id: AppEntry.ID) async {
        var ids = selection
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        await select(ids)
    }

    func uninstall() async {
        let chosen = selectedApps
        guard !chosen.isEmpty else { return }
        busy = true
        var waited = false
        for app in chosen {
            guard let bid = app.bundleID else { continue }
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: bid) {
                running.terminate()
                waited = true
            }
        }
        if waited { try? await Task.sleep(for: .seconds(1.5)) }
        let urls = chosen.map(\.url) + leftovers.filter(\.selected).map(\.url)
        let error = await Remover.moveToTrash(urls)
        busy = false
        message = error ?? (chosen.count == 1 ? "\(chosen[0].name) wurde in den Papierkorb gelegt."
                                             : "\(chosen.count) Programme wurden in den Papierkorb gelegt.")
        if error == nil {
            selection = []
            leftovers = []
        }
        await loadApps()
        DiskModel.shared.refresh()
    }

    func scanOrphans() async {
        orphanBusy = true
        let installed = apps.isEmpty ? await Task.detached { AppScanner.findApps() }.value : apps
        let found = await Task.detached { AppScanner.orphans(installed: installed) }.value
        let s = await DiskUsage.sizes(found.map { $0.0.path })
        orphans = found.map { Leftover(url: $0.0, size: s[$0.0.path] ?? 0, note: $0.1, selected: false) }
            .sorted { $0.size > $1.size }
        orphanBusy = false
        orphansScanned = true
    }

    func removeOrphans() async {
        orphanBusy = true
        let error = await Remover.moveToTrash(orphans.filter(\.selected).map(\.url))
        message = error ?? "Ausgewählte Reste wurden in den Papierkorb gelegt."
        await scanOrphans()
    }
}
