import Foundation

/// Runs every scanner once without changing anything and prints a summary.
/// Start with: /Applications/MacCleaner.app/Contents/MacOS/MacCleaner --selftest
enum SelfTest {
    @MainActor
    static func run() async {
        func line(_ s: String) { print(s); fflush(stdout) }

        DiskModel.shared.refresh()
        line("== Speicher: \(Fmt.bytes(DiskModel.shared.free)) frei von \(Fmt.bytes(DiskModel.shared.total))")

        let clean = CleanupModel.shared
        await clean.scan()
        line("== Aufräumen (vorausgewählt: \(Fmt.bytes(clean.selectedTotal)))")
        for c in clean.categories {
            line("  \(c.selected ? "[x]" : "[ ]") \(c.name): \(Fmt.bytes(c.total)) in \(c.items.count) Einträgen\(c.noAccess ? " – KEIN ZUGRIFF" : "")")
        }

        let apps = AppScanner.findApps()
        line("== Programme: \(apps.count) gefunden")
        for name in ["TeamViewer", "CleanMyMac", "Parallels Desktop"] {
            guard let app = apps.first(where: { $0.name.hasPrefix(name) }) else { continue }
            let found = AppScanner.leftovers(for: app)
            line("  \(app.name) (\(app.bundleID ?? "-")): \(found.filter { $0.2 }.count) Reste, \(found.filter { !$0.2 }.count) vom Hersteller")
            for f in found.prefix(8) { line("     \(mark(f.2)) \(Fmt.path(f.0.path))") }
        }
        // Already-removed app as an example: are its leftovers (incl. old version 4) found?
        let fake = AppEntry(url: URL(fileURLWithPath: "/Applications/CleanMyMac_5.app"), name: "CleanMyMac_5",
                            bundleID: "com.macpaw.CleanMyMac5")
        let fakeFound = AppScanner.leftovers(for: fake)
        line("  Probe CleanMyMac_5 (entfernt): \(fakeFound.filter { $0.2 }.count) Reste vorausgewählt, \(fakeFound.filter { !$0.2 }.count) nicht")
        for f in fakeFound { line("     \(mark(f.2)) \(Fmt.path(f.0.path)) – \(f.1)") }
        let orphans = AppScanner.orphans(installed: apps)
        line("== Reste ohne Programm: \(orphans.count)")
        for o in orphans.prefix(10) { line("  \(Fmt.path(o.0.path)) – \(o.1)") }

        let big = await SpaceScanner.bigFiles(minBytes: 1_000_000_000)
        line("== Dateien > 1 GB: \(big.count)")
        for b in big.prefix(5) { line("  \(Fmt.bytes(b.size))  \(Fmt.path(b.url.path))") }

        let dl = await SpaceScanner.children(of: home.appendingPathComponent("Downloads"))
        line("== Größte Einträge in ~/Downloads: \(dl.prefix(3).map { "\($0.url.lastPathComponent) \(Fmt.bytes($0.size))" }.joined(separator: ", "))")

        let sec = SecurityModel.shared
        await sec.scan()
        line("== Sicherheit: \(sec.statusText)")
        for c in sec.checks where c.level >= .warn { line("  ⚠️ \(c.title): \(c.detail)") }
        for a in sec.autostart where a.level >= .info { line("  [\(a.level)] \(a.label): \(a.note)") }
        line("  Autostart gesamt: \(sec.autostart.count), davon OK: \(sec.autostart.filter { $0.level == .ok }.count)")
        for p in sec.processes { line("  Prozess [\(p.level)] \(Fmt.path(p.path)): \(p.note)") }

        let ms = MemoryStats.snapshot()
        line("== Arbeitsspeicher: \(Fmt.bytes(ms.used)) von \(Fmt.bytes(ms.total)) in Gebrauch, Vorrat \(Fmt.bytes(ms.cached)), Druck: \(ms.pressure.text)")
        for u in MemoryStats.topUsers(limit: 5) { line("  \(Fmt.bytes(u.bytes))  \(u.name) (\(u.processes) Prozesse)") }

        let mal = MalwareModel.shared
        await mal.scan()
        line("== Malware-Suche: \(mal.statusText) · XProtect \(mal.protection.xprotect), Auto-Updates: \(mal.protection.autoUpdates ? "an" : "AUS")")
        for t in mal.threats where t.kind != .extensions || t.level >= .warn {
            line("  [\(t.level)] \(t.kind.rawValue): \(t.title) – \(t.detail.replacingOccurrences(of: "\n", with: " | "))")
        }
        line("  Browser-Erweiterungen: \(mal.threats.filter { $0.kind == .extensions }.map(\.title).joined(separator: ", "))")

        line("== Wartung: \(MaintenanceModel.shared.tasks.map(\.title).joined(separator: ", "))")
    }

    private static func mark(_ preselected: Bool) -> String { preselected ? "[x]" : "[ ]" }
}
