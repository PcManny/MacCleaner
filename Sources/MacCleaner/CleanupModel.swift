import Foundation

@MainActor
final class DiskModel: ObservableObject {
    static let shared = DiskModel()
    @Published var free: Int64 = 0
    @Published var total: Int64 = 0
    private var timer: Timer?

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in DiskModel.shared.refresh() }
        }
    }

    func refresh() {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys)
        free = v?.volumeAvailableCapacityForImportantUsage ?? 0
        total = Int64(v?.volumeTotalCapacity ?? 0)
    }

    var used: Int64 { max(total - free, 0) }
    var usedFraction: Double { total > 0 ? Double(used) / Double(total) : 0 }
}

struct CleanItem: Identifiable {
    let url: URL
    let size: Int64
    var id: String { url.path }
}

struct CleanCategory: Identifiable {
    enum Kind { case moveToTrash, emptyTrash }

    let id: String
    let name: String
    let detail: String
    let icon: String
    var kind: Kind = .moveToTrash
    var selected: Bool
    let collect: @Sendable () -> [URL]?   // nil = no permission to read

    var items: [CleanItem] = []
    var excluded: Set<String> = []
    var noAccess = false

    var total: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedItems: [CleanItem] { items.filter { !excluded.contains($0.id) } }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }

    /// Ein einzelner Eintrag zählt nur, wenn auch der ganze Bereich angehakt ist.
    func isItemOn(_ id: String) -> Bool { selected && !excluded.contains(id) }

    /// Kleines Kästchen geklickt: großes Kästchen passt sich an.
    mutating func setItem(_ id: String, on: Bool) {
        if on {
            if !selected {            // erster Haken in einem leeren Bereich: nur diesen einen nehmen
                selected = true
                excluded = Set(items.map(\.id))
            }
            excluded.remove(id)
        } else {
            excluded.insert(id)
            if items.allSatisfy({ excluded.contains($0.id) }) { selected = false; excluded = [] }
        }
    }

    /// Großes Kästchen geklickt: alle Einträge an oder aus.
    mutating func setAll(_ on: Bool) {
        selected = on
        excluded = []
    }
}

@MainActor
final class CleanupModel: ObservableObject {
    static let shared = CleanupModel()

    @Published var categories: [CleanCategory] = CleanupModel.definitions()
    @Published var scanning = false
    @Published var cleaning = false
    @Published var lastScan: Date?
    @Published var message: String?
    @Published var needsFullDiskAccess = false

    var selectedTotal: Int64 {
        categories.filter { $0.selected }.reduce(0) { $0 + $1.selectedSize }
    }

    /// Categories that are always safe to clean: they are rebuilt automatically.
    static let safeIDs: Set<String> = ["caches", "logs", "xcode"]
    var safeCategories: [CleanCategory] { categories.filter { Self.safeIDs.contains($0.id) && !$0.items.isEmpty } }
    var safeTotal: Int64 { safeCategories.reduce(0) { $0 + $1.total } }
    var trashTotal: Int64 { categories.first { $0.kind == .emptyTrash }?.total ?? 0 }
    @Published var quickMessage: String?

    /// "Alles aufräumen": only the safe categories, all their items. Optionally empty the Trash afterwards.
    func quickClean(emptyTrash: Bool) async {
        guard !cleaning else { return }
        cleaning = true
        quickMessage = nil
        let freed = safeTotal
        var error = await Remover.moveToTrash(safeCategories.flatMap { $0.items.map(\.url) })
        if emptyTrash {
            switch await Remover.emptyTrash() {
            case .done: break
            case .noAccess:
                needsFullDiskAccess = true
                error = "Der Papierkorb konnte nicht geleert werden, weil MacCleaner der Festplattenvollzugriff fehlt (siehe Einstellungen)."
            case .failed(let names):
                error = "Einiges im Papierkorb wurde nicht gelöscht (\(names.prefix(2).joined(separator: ", "))…)."
            }
        }
        cleaning = false
        quickMessage = error ?? (emptyTrash
            ? "Fertig – \(Fmt.bytes(freed)) aufgeräumt und der Papierkorb ist leer."
            : "Fertig – \(Fmt.bytes(freed)) liegen im Papierkorb. Leere ihn, um den Platz freizugeben.")
        await scan()
        DiskModel.shared.refresh()
    }

    var trashSelected: Bool {
        categories.contains { $0.selected && $0.kind == .emptyTrash }
    }

    func scan() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false }
        for i in categories.indices {
            let collect = categories[i].collect
            let urls = await Task.detached { collect() }.value
            if let urls {
                let sizes = await DiskUsage.sizes(urls.map(\.path))
                categories[i].items = urls
                    .map { CleanItem(url: $0, size: sizes[$0.path] ?? 0) }
                    .sorted { $0.size > $1.size }
                categories[i].noAccess = false
            } else {
                categories[i].items = []
                categories[i].noAccess = true
            }
            categories[i].excluded = []
        }
        lastScan = Date()
    }

    func clean() async {
        cleaning = true
        message = nil
        let freed = selectedTotal
        let urls = categories
            .filter { $0.selected && $0.kind == .moveToTrash }
            .flatMap { $0.selectedItems.map(\.url) }
        var error = await Remover.moveToTrash(urls)
        needsFullDiskAccess = false
        if trashSelected {
            switch await Remover.emptyTrash() {
            case .done: break
            case .noAccess:
                needsFullDiskAccess = true
                error = "Der Papierkorb konnte nicht geleert werden, weil MacCleaner der Festplattenvollzugriff fehlt."
            case .failed(let names):
                let list = names.prefix(3).map { "„\($0)“" }.joined(separator: ", ") + (names.count > 3 ? " …" : "")
                error = "Nicht gelöscht: \(list). Abgebrochen oder vom System geschützt."
            }
        }
        cleaning = false
        message = error ?? (trashSelected
            ? "Fertig – \(Fmt.bytes(freed)) freigegeben."
            : "Fertig – \(Fmt.bytes(freed)) liegen im Papierkorb. Leere ihn, um den Platz freizugeben.")
        await scan()
        DiskModel.shared.refresh()
    }

    static func definitions() -> [CleanCategory] {
        [
            CleanCategory(
                id: "caches", name: "Programm-Caches",
                detail: "Zwischenspeicher von Programmen. Sie werden bei Bedarf neu angelegt. Apple-eigene Caches bleiben unangetastet.",
                icon: "archivebox", selected: true,
                collect: { FS.children(FS.h("Library/Caches")) { $0.hasPrefix("com.apple.") || $0 == "CloudKit" || $0 == "FamilyCircle" } }),
            CleanCategory(
                id: "logs", name: "Protokolle & Absturzberichte",
                detail: "Protokolldateien von Programmen. Nur zur Fehlersuche nötig.",
                icon: "doc.text", selected: true,
                collect: { FS.children(FS.h("Library/Logs")) }),
            CleanCategory(
                id: "xcode", name: "Xcode & Simulator",
                detail: "Build-Zwischenstände, Gerätesymbole und Simulator-Caches. Werden beim nächsten Build neu erzeugt.",
                icon: "hammer", selected: true,
                collect: {
                    ["Library/Developer/Xcode/DerivedData", "Library/Developer/Xcode/iOS DeviceSupport",
                     "Library/Developer/Xcode/macOS DeviceSupport", "Library/Developer/CoreSimulator/Caches"]
                        .flatMap { FS.children(FS.h($0)) ?? [] }
                }),
            CleanCategory(
                id: "dev", name: "Entwickler-Caches",
                detail: "npm, Gradle, pip und allgemeine ~/.cache-Ordner. Pakete werden bei Bedarf neu geladen – bitte kurz ansehen.",
                icon: "shippingbox", selected: false,
                collect: { FS.existing([".npm/_cacache", ".cache", ".gradle/caches", ".cocoapods/repos"].map(FS.h)) }),
            CleanCategory(
                id: "downloads", name: "Alte Downloads",
                detail: "Dateien im Download-Ordner, die seit über 90 Tagen nicht verändert wurden. Bitte vorher durchsehen.",
                icon: "arrow.down.circle", selected: false,
                collect: {
                    let cutoff = Date().addingTimeInterval(-90 * 86400)
                    guard let all = FS.children(FS.h("Downloads")) else { return nil }
                    return all.filter { u in
                        let v = try? u.resourceValues(forKeys: [.contentModificationDateKey, .addedToDirectoryDateKey])
                        let modified = v?.contentModificationDate ?? .distantPast
                        let added = v?.addedToDirectoryDate ?? modified
                        return max(modified, added) < cutoff
                    }
                }),
            CleanCategory(
                id: "mail", name: "Mail-Anhänge",
                detail: "Von Mail zwischengespeicherte Anhänge. Die Anhänge bleiben in den E-Mails erhalten.",
                icon: "paperclip", selected: false,
                collect: { FS.children(FS.h("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")) }),
            CleanCategory(
                id: "iosbackup", name: "iPhone-/iPad-Backups",
                detail: "Lokale Gerätesicherungen. Nur löschen, wenn du sie nicht mehr brauchst!",
                icon: "iphone", selected: false,
                collect: { FS.children(FS.h("Library/Application Support/MobileSync/Backup")) }),
            CleanCategory(
                id: "trash", name: "Papierkorb leeren",
                detail: "Leert den Papierkorb endgültig – auch alles, was hier gerade aufgeräumt wird. Nicht rückgängig zu machen.",
                icon: "trash", kind: .emptyTrash, selected: false,
                collect: { FS.children(FS.h(".Trash")) }),
        ]
    }
}
