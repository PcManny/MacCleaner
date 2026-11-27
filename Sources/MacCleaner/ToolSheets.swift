import AppKit
import SwiftUI

// MARK: - Sheet frame

struct ToolSheetView: View {
    let sheet: ToolSheet
    @Environment(\.dismiss) private var dismiss

    private var tool: Tool? {
        Tool.all.first { if case .sheet(let s) = $0.action { return s == sheet } else { return false } }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let tool { IconTile(symbol: tool.icon, color: tool.color, size: 40) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(tool?.title ?? "").font(.title2.bold())
                    Text(tool?.detail ?? "").foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Schließen") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(16)
            .background {
                if let tool {
                    LinearGradient(colors: [tool.color.opacity(0.2), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            Divider()
            content
        }
        .frame(width: 760, height: 560)
    }

    @ViewBuilder private var content: some View {
        switch sheet {
        case .downloads: FindingsToolView(collect: ToolCollect.downloads, intro:
            "Alles im Download-Ordner, das Größte zuerst. Nichts ist vorausgewählt – hake an, was weg kann.")
        case .mail: FindingsToolView(collect: ToolCollect.mail, intro:
            "Mail legt hier Kopien von Anhängen ab, die du geöffnet hast. In den E-Mails bleiben sie erhalten. Hast du einen Anhang hier bearbeitet und nicht woanders gespeichert, ist das die einzige Fassung – darum ist nichts vorausgewählt.")
        case .systemJunk: FindingsToolView(collect: ToolCollect.systemJunk, intro:
            "Caches und Protokolle werden von den Programmen bei Bedarf neu angelegt. Apple-eigene Caches bleiben unangetastet.")
        case .aiJunk: FindingsToolView(collect: ToolCollect.aiJunk, intro:
            "Zwischenspeicher sind vorausgewählt. Heruntergeladene KI-Modelle und Daten von gerade laufenden Programmen sind es nicht – sie müssten neu geladen werden.")
        case .trash: TrashToolView()
        case .timeMachine: SnapshotToolView()
        case .screenClean: ScreenCleanToolView()
        case .permissions: PermissionsToolView()
        case .background: BackgroundToolView()
        }
    }
}

// MARK: - Generic "find files, tick, move to Trash" tool

struct Finding: Identifiable {
    let url: URL
    var size: Int64 = 0
    let note: String
    var selected: Bool
    var id: String { url.path }
}

/// What a collector returns: path, explanation, preselected? – or nil when there is no permission to read.
typealias Found = (url: URL, note: String, preselect: Bool)

@MainActor
final class FindingsModel: ObservableObject {
    @Published var items: [Finding] = []
    @Published var busy = false
    @Published var scanned = false
    @Published var noAccess = false
    @Published var message: String?
    let collect: @Sendable () -> [Found]?

    init(collect: @escaping @Sendable () -> [Found]?) { self.collect = collect }

    var selectedSize: Int64 { items.filter(\.selected).reduce(0) { $0 + $1.size } }
    var selectedCount: Int { items.filter(\.selected).count }

    func scan() async {
        busy = true
        let collect = collect
        let found = await Task.detached(priority: .userInitiated) { collect() }.value
        noAccess = found == nil
        let list = found ?? []
        let sizes = await DiskUsage.sizes(list.map(\.url.path))
        items = list.map { Finding(url: $0.url, size: sizes[$0.url.path] ?? 0, note: $0.note, selected: $0.preselect) }
            .filter { $0.size > 0 }
            .sorted { $0.size > $1.size }
        busy = false
        scanned = true
    }

    func trash() async {
        let chosen = items.filter(\.selected)
        let freed = chosen.reduce(0) { $0 + $1.size }
        message = await Remover.moveToTrash(chosen.map(\.url))
            ?? "Fertig – \(Fmt.bytes(freed)) liegen im Papierkorb. Leere ihn, um den Platz freizugeben."
        await scan()
        DiskModel.shared.refresh()
    }
}

struct FindingsToolView: View {
    @StateObject private var m: FindingsModel
    let intro: String
    @State private var confirm = false

    init(collect: @escaping @Sendable () -> [Found]?, intro: String) {
        _m = StateObject(wrappedValue: FindingsModel(collect: collect))
        self.intro = intro
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(intro).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(16)
            if m.busy && !m.scanned {
                ProgressView("Wird durchsucht …").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if m.noAccess {
                ContentUnavailableView {
                    Label("Kein Zugriff", systemImage: "lock")
                } description: {
                    Text("MacCleaner braucht dafür den Festplattenvollzugriff.")
                } actions: {
                    Button("Festplattenvollzugriff erlauben …") { SettingsPane.open(SettingsPane.fullDisk) }
                }
            } else if m.items.isEmpty {
                ContentUnavailableView("Nichts gefunden", systemImage: "checkmark.circle",
                                       description: Text("Hier gibt es gerade nichts aufzuräumen."))
            } else {
                List {
                    ForEach($m.items) { $f in
                        HStack(spacing: 10) {
                            Toggle("", isOn: $f.selected).toggleStyle(.checkbox).labelsHidden()
                            Image(nsImage: appIcon(f.url.path)).resizable().frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(f.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                Text(f.note).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Text(Fmt.bytes(f.size)).monospacedDigit().foregroundStyle(.secondary)
                            Button { reveal(f.url) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.borderless).help("Im Finder zeigen")
                        }
                    }
                }
            }
            Footer {
                if let msg = m.message { Text(msg).foregroundStyle(.secondary).lineLimit(2) }
                Spacer()
                if m.busy { ProgressView().controlSize(.small) }
                if !m.items.isEmpty {
                    Button(m.selectedCount == m.items.count ? "Keine" : "Alle") {
                        let all = m.selectedCount != m.items.count
                        for i in m.items.indices { m.items[i].selected = all }
                    }
                }
                Text("Ausgewählt: \(Fmt.bytes(m.selectedSize))").bold()
                Button("In den Papierkorb …") { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(m.selectedCount == 0 || m.busy)
            }
        }
        .task { await m.scan() }
        .confirmationDialog("In den Papierkorb legen?", isPresented: $confirm) {
            Button("\(m.selectedCount) Einträge in den Papierkorb") { Task { await m.trash() } }
        } message: {
            Text("\(Fmt.bytes(m.selectedSize)) werden in den Papierkorb gelegt. Du kannst sie von dort zurückholen.")
        }
    }
}

enum ToolCollect {
    private static let dateFmt: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; f.locale = Locale(identifier: "de_DE"); return f
    }()

    static let downloads: @Sendable () -> [Found]? = {
        guard let kids = FS.children(FS.h("Downloads")) else { return nil }
        return kids.map { u in
            let v = try? u.resourceValues(forKeys: [.addedToDirectoryDateKey, .contentModificationDateKey])
            let d = v?.addedToDirectoryDate ?? v?.contentModificationDate
            return (u, d.map { "geladen am \(dateFmt.string(from: $0))" } ?? "", false)
        }
    }

    static let mail: @Sendable () -> [Found]? = {
        guard let kids = FS.children(FS.h("Library/Containers/com.apple.mail/Data/Library/Mail Downloads")) else { return nil }
        return kids.map { ($0, "Kopie eines Mail-Anhangs", false) }
    }

    static let systemJunk: @Sendable () -> [Found]? = {
        guard let caches = FS.children(FS.h("Library/Caches"), exclude: {
            $0.hasPrefix("com.apple.") || $0 == "CloudKit" || $0 == "FamilyCircle"
        }) else { return nil }
        var out: [Found] = caches.map { ($0, "Programm-Cache", true) }
        out += (FS.children(FS.h("Library/Logs")) ?? []).map { ($0, "Protokoll", true) }
        for p in ["Library/Developer/Xcode/DerivedData", "Library/Developer/Xcode/iOS DeviceSupport",
                  "Library/Developer/Xcode/macOS DeviceSupport", "Library/Developer/CoreSimulator/Caches"] {
            out += (FS.children(FS.h(p)) ?? []).map { ($0, "Xcode-Zwischenstand", true) }
        }
        return out
    }

    /// AI apps: caches are preselected unless the app is running; models and VMs never are.
    static let aiJunk: @Sendable () -> [Found]? = {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var out: [Found] = []
        func add(_ rel: String, _ note: String, safe: Bool, app: String? = nil) {
            let path = FS.h(rel)
            guard FileManager.default.fileExists(atPath: path) else { return }
            let isRunning = app.map { running.contains($0) } ?? false
            out.append((URL(fileURLWithPath: path), isRunning ? note + " – Programm läuft gerade, erst beenden" : note,
                        safe && !isRunning))
        }
        let claude = "com.anthropic.claudefordesktop"
        for c in ["Cache", "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache", "GraphiteDawnCache",
                  "GPUPersistentCache", "Crashpad", "Extensions Update Cache"] {
            add("Library/Application Support/Claude/\(c)", "Claude: Zwischenspeicher", safe: true, app: claude)
        }
        add("Library/Application Support/Claude/vm_bundles",
            "Claude: Arbeitsumgebung für Cowork – nur löschen, wenn du Cowork nicht nutzt", safe: false, app: claude)
        add("Library/Logs/Claude", "Claude: Protokolle", safe: true, app: claude)
        add("Library/Application Support/ChatGPT/Cache", "ChatGPT: Zwischenspeicher", safe: true, app: "com.openai.chat")
        add("Library/Application Support/Cursor/Cache", "Cursor: Zwischenspeicher", safe: true, app: "com.todesktop.230313mzl4w4u92")
        add("Library/Application Support/Cursor/CachedData", "Cursor: Zwischenspeicher", safe: true, app: "com.todesktop.230313mzl4w4u92")
        add(".ollama/models", "Ollama: heruntergeladene KI-Modelle (müssten neu geladen werden)", safe: false)
        add(".lmstudio/models", "LM Studio: heruntergeladene KI-Modelle (müssten neu geladen werden)", safe: false)
        add(".cache/lm-studio", "LM Studio: Zwischenspeicher", safe: false)
        add(".cache/huggingface", "Hugging Face: heruntergeladene Modelle (müssten neu geladen werden)", safe: false)
        add(".cache/whisper", "Whisper: Sprachmodelle (müssten neu geladen werden)", safe: false)
        add(".diffusionbee", "DiffusionBee: Bildmodelle (müssten neu geladen werden)", safe: false)
        // Caches folders named after AI tools
        let words = ["openai", "chatgpt", "anthropic", "claude", "ollama", "lmstudio", "perplexity", "copilot", "gemini", "cursor"]
        for u in FS.children(FS.h("Library/Caches")) ?? [] {
            let n = u.lastPathComponent.lowercased()
            guard words.contains(where: { n.contains($0) }) else { continue }
            let isRunning = running.contains { n.hasPrefix($0.lowercased()) }
            out.append((u, isRunning ? "Cache – Programm läuft gerade, erst beenden" : "Cache eines KI-Programms", !isRunning))
        }
        return out
    }
}

// MARK: - Trash

struct TrashToolView: View {
    @State private var size: Int64 = 0
    @State private var count = 0
    @State private var noAccess = false
    @State private var busy = true
    @State private var confirm = false
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            if busy {
                ProgressView("Papierkorb wird geprüft …")
            } else if noAccess {
                ContentUnavailableView {
                    Label("Kein Zugriff", systemImage: "lock")
                } description: {
                    Text("Um in den Papierkorb zu schauen, braucht MacCleaner den Festplattenvollzugriff.")
                } actions: {
                    Button("Festplattenvollzugriff erlauben …") { SettingsPane.open(SettingsPane.fullDisk) }
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: count == 0 ? "trash" : "trash.fill").font(.system(size: 64)).foregroundStyle(.secondary)
                    Text(count == 0 ? "Der Papierkorb ist leer." : "\(Fmt.bytes(size)) im Papierkorb")
                        .font(.title.bold())
                    if count > 0 { Text("\(count) Einträge").foregroundStyle(.secondary) }
                    HStack {
                        Button("Im Finder öffnen") { NSWorkspace.shared.open(URL(fileURLWithPath: FS.h(".Trash"))) }
                        Button("Papierkorb leeren …", role: .destructive) { confirm = true }
                            .buttonStyle(.borderedProminent).disabled(count == 0)
                    }
                    .padding(.top, 8)
                }
            }
            Spacer()
            if let message { Footer { Text(message).foregroundStyle(.secondary); Spacer() } }
        }
        .task { await refresh() }
        .confirmationDialog("Papierkorb endgültig leeren?", isPresented: $confirm) {
            Button("Endgültig leeren", role: .destructive) { Task { await empty() } }
        } message: {
            Text("\(Fmt.bytes(size)) werden endgültig gelöscht. Das lässt sich nicht rückgängig machen.")
        }
    }

    private func refresh() async {
        busy = true
        if let kids = FS.children(FS.h(".Trash")) {
            noAccess = false
            count = kids.count
            size = await DiskUsage.sizes(kids.map(\.path)).values.reduce(0, +)
        } else {
            noAccess = true
        }
        busy = false
    }

    private func empty() async {
        busy = true
        switch await Remover.emptyTrash() {
        case .done: message = "Fertig – der Papierkorb ist leer."
        case .noAccess: message = "Dafür fehlt der Festplattenvollzugriff (siehe Einstellungen)."
        case .failed(let names): message = "Nicht gelöscht: \(names.prefix(3).joined(separator: ", "))."
        }
        await refresh()
        DiskModel.shared.refresh()
    }
}

// MARK: - Time Machine snapshots

struct SnapshotToolView: View {
    @State private var dates: [String] = []
    @State private var selected: Set<String> = []
    @State private var busy = true
    @State private var confirm = false
    @State private var message: String?
    @State private var purgeable: Int64 = 0

    private static let parser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd-HHmmss"; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Time Machine legt auf dem Mac selbst kurzzeitig Schnappschüsse an, damit du auch ohne Backup-Platte Dateien zurückholen kannst. macOS löscht sie nach 24 Stunden oder wenn der Platz knapp wird von selbst. Entfernen lohnt sich vor allem, wenn ein Programm über zu wenig Platz klagt. Gelöschte Schnappschüsse sind endgültig weg – deine Backups auf der Time-Machine-Platte bleiben unberührt.")
                .foregroundStyle(.secondary).padding(16)
            if busy && dates.isEmpty {
                ProgressView("Schnappschüsse werden gesucht …").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if dates.isEmpty {
                ContentUnavailableView("Keine lokalen Schnappschüsse", systemImage: "checkmark.circle")
            } else {
                List(dates, id: \.self) { d in
                    HStack {
                        Toggle("", isOn: Binding(get: { selected.contains(d) },
                                                 set: { if $0 { selected.insert(d) } else { selected.remove(d) } }))
                            .toggleStyle(.checkbox).labelsHidden()
                        Image(systemName: "clock.arrow.circlepath").foregroundStyle(.orange)
                        Text(Self.parser.date(from: d).map(Fmt.date) ?? d)
                        Spacer()
                        Text(d).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
            Footer {
                VStack(alignment: .leading) {
                    if purgeable > 0 { Text("Freigebbarer Speicher (u. a. Schnappschüsse): \(Fmt.bytes(purgeable))").font(.callout) }
                    if let message { Text(message).foregroundStyle(.secondary) }
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                if !dates.isEmpty {
                    Button(selected.count == dates.count ? "Keine" : "Alle") {
                        selected = selected.count == dates.count ? [] : Set(dates)
                    }
                }
                Button("Entfernen …", role: .destructive) { confirm = true }
                    .buttonStyle(.borderedProminent).disabled(selected.isEmpty || busy)
            }
        }
        .task { await refresh() }
        .confirmationDialog("\(selected.count) Schnappschüsse entfernen?", isPresented: $confirm) {
            Button("Endgültig entfernen", role: .destructive) { Task { await delete() } }
        } message: {
            Text("Die lokalen Schnappschüsse werden gelöscht (nicht in den Papierkorb). macOS fragt nach deinem Passwort.")
        }
    }

    private func refresh() async {
        busy = true
        let out = await Shell.run("/usr/bin/tmutil", ["listlocalsnapshotdates", "/"]).out
        dates = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil }
            .sorted(by: >)
        selected = selected.intersection(dates)
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        if let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
           let important = v.volumeAvailableCapacityForImportantUsage, let plain = v.volumeAvailableCapacity {
            purgeable = max(important - Int64(plain), 0)
        }
        busy = false
    }

    private func delete() async {
        busy = true
        let cmd = selected.sorted().map { "/usr/bin/tmutil deletelocalsnapshots \($0)" }.joined(separator: "; ")
        let n = selected.count
        let ok = await Shell.admin(cmd)
        message = ok ? "\(n) Schnappschüsse entfernt." : "Abgebrochen oder fehlgeschlagen."
        selected = []
        await refresh()
        DiskModel.shared.refresh()
    }
}

// MARK: - Screen cleaning mode

struct ScreenCleanToolView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sparkles.tv").font(.system(size: 64)).foregroundStyle(.pink)
            Text("Bildschirm und Tastatur putzen").font(.title.bold())
            VStack(alignment: .leading, spacing: 8) {
                Label("Der Bildschirm wird schwarz – so sieht man Staub und Schlieren am besten.", systemImage: "moon.fill")
                Label("Tastatur, Maus und Trackpad sind gesperrt. Du kannst gefahrlos darüber wischen.", systemImage: "keyboard")
                Label("Zum Beenden die Taste **esc** 2 Sekunden lang gedrückt halten.", systemImage: "escape")
                Label("Nach 3 Minuten endet der Modus von selbst.", systemImage: "timer")
            }
            .frame(maxWidth: 520, alignment: .leading)
            Button("Putzmodus starten") {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ScreenCleaner.start() }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }
        .padding()
    }
}

/// Borderless window that can take the keyboard.
private final class CleanWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ScreenCleaner: ObservableObject {
    static let shared = ScreenCleaner()
    @Published var escSince: Date?
    @Published var endsAt = Date()
    private var windows: [NSWindow] = []
    private var monitor: Any?
    private var timer: Timer?

    static func start() { shared.begin() }

    private func begin() {
        guard windows.isEmpty else { return }
        endsAt = Date().addingTimeInterval(180)
        escSince = nil
        for screen in NSScreen.screens {
            let w = CleanWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = .screenSaver
            w.backgroundColor = .black
            w.isReleasedWhenClosed = false
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.contentView = NSHostingView(rootView: CleanScreenView(cleaner: self))
            w.setFrame(screen.frame, display: true)
            w.orderFrontRegardless()
            windows.append(w)
        }
        windows.first?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.presentationOptions = [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableForceQuit,
                                     .disableSessionTermination, .disableHideApplication, .disableAppleMenu]
        NSCursor.hide()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp,
                                                              .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp,
                                                              .scrollWheel, .mouseMoved, .leftMouseDragged, .rightMouseDragged,
                                                              .magnify, .rotate, .swipe, .smartMagnify]) { [weak self] e in
            self?.handle(e)
            return nil   // swallow everything
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func handle(_ e: NSEvent) {
        guard e.type == .keyDown || e.type == .keyUp, e.keyCode == 53 else { return }   // 53 = esc
        if e.type == .keyDown { if escSince == nil { escSince = Date() } } else { escSince = nil }
    }

    private func tick() {
        if let s = escSince, Date().timeIntervalSince(s) >= 2 { stop(); return }
        if Date() >= endsAt { stop() }
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NSApp.presentationOptions = []
        NSCursor.unhide()
        windows.forEach { $0.orderOut(nil) }
        windows = []
        escSince = nil
    }
}

private struct CleanScreenView: View {
    @ObservedObject var cleaner: ScreenCleaner

    var body: some View {
        ZStack {
            Color.black
            TimelineView(.periodic(from: .now, by: 0.2)) { ctx in
                VStack(spacing: 12) {
                    Text("Putzmodus").font(.system(size: 28, weight: .semibold))
                    if let s = cleaner.escSince {
                        let left = max(0, 2 - ctx.date.timeIntervalSince(s))
                        Text("Weiter gedrückt halten … \(String(format: "%.1f", left)) s")
                    } else {
                        Text("Zum Beenden **esc** 2 Sekunden lang gedrückt halten")
                    }
                    let rest = max(0, Int(cleaner.endsAt.timeIntervalSince(ctx.date)))
                    Text("Endet von selbst in \(rest / 60):\(String(format: "%02d", rest % 60))").font(.callout)
                }
                .foregroundStyle(Color(white: 0.28))
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - App permissions (read from the privacy database, read-only)

struct PermissionGroup: Identifiable {
    let title: String
    let icon: String
    let anchor: String
    var apps: [(name: String, path: String?)]
    var id: String { anchor }
}

struct PermissionsToolView: View {
    @State private var groups: [PermissionGroup] = []
    @State private var readable = true
    @State private var busy = true

    /// TCC service → (title, symbol, anchor in System Settings › Privacy & Security)
    private static let services: [(String, String, String, String)] = [
        ("kTCCServiceSystemPolicyAllFiles", "Festplattenvollzugriff", "internaldrive", "Privacy_AllFiles"),
        ("kTCCServiceAccessibility", "Bedienungshilfen (Mac steuern)", "accessibility", "Privacy_Accessibility"),
        ("kTCCServiceScreenCapture", "Bildschirm aufnehmen", "rectangle.dashed.badge.record", "Privacy_ScreenCapture"),
        ("kTCCServiceListenEvent", "Eingabeüberwachung (Tastatur)", "keyboard", "Privacy_ListenEvent"),
        ("kTCCServiceCamera", "Kamera", "camera", "Privacy_Camera"),
        ("kTCCServiceMicrophone", "Mikrofon", "mic", "Privacy_Microphone"),
        ("kTCCServicePhotos", "Fotos", "photo", "Privacy_Photos"),
        ("kTCCServiceAddressBook", "Kontakte", "person.crop.circle", "Privacy_Contacts"),
        ("kTCCServiceCalendar", "Kalender", "calendar", "Privacy_Calendars"),
        ("kTCCServiceReminders", "Erinnerungen", "checklist", "Privacy_Reminders"),
        ("kTCCServiceBluetoothAlways", "Bluetooth", "dot.radiowaves.left.and.right", "Privacy_Bluetooth"),
        ("kTCCServiceSystemPolicyDesktopFolder", "Ordner „Schreibtisch“", "menubar.dock.rectangle", "Privacy_FilesAndFolders"),
        ("kTCCServiceSystemPolicyDocumentsFolder", "Ordner „Dokumente“", "doc", "Privacy_FilesAndFolders"),
        ("kTCCServiceSystemPolicyDownloadsFolder", "Ordner „Downloads“", "arrow.down.circle", "Privacy_FilesAndFolders"),
        ("kTCCServiceSystemPolicyNetworkVolumes", "Netzwerk-Laufwerke", "network", "Privacy_FilesAndFolders"),
        ("kTCCServiceSystemPolicyRemovableVolumes", "Wechseldatenträger (USB)", "externaldrive", "Privacy_FilesAndFolders"),
        ("kTCCServiceAppleEvents", "Automation (andere Programme steuern)", "gearshape.2", "Privacy_Automation"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text("Hier siehst du, welchen Programmen du welche Rechte gegeben hast. Ändern kannst du sie in den Systemeinstellungen – ein Klick auf „Ändern …“ öffnet die richtige Stelle. Kennst du ein Programm nicht oder brauchst es nicht mehr, nimm ihm das Recht weg.")
                .foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            if busy {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !readable {
                        Label("Die Liste der Programme kann MacCleaner nur mit Festplattenvollzugriff lesen. Die Knöpfe führen trotzdem zur richtigen Einstellung.",
                              systemImage: "lock").foregroundStyle(.orange)
                    }
                    ForEach(groups) { g in
                        Section {
                            if readable && g.apps.isEmpty {
                                Text("Kein Programm").foregroundStyle(.secondary)
                            }
                            ForEach(g.apps, id: \.name) { a in
                                HStack {
                                    if let p = a.path {
                                        Image(nsImage: appIcon(p)).resizable().frame(width: 20, height: 20)
                                    } else {
                                        Image(systemName: "terminal").frame(width: 20)
                                    }
                                    Text(a.name)
                                }
                            }
                        } header: {
                            HStack {
                                Label(g.title, systemImage: g.icon)
                                Spacer()
                                Button("Ändern …") { SettingsPane.open(SettingsPane.privacy + "?" + g.anchor) }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        let dbs = [FS.h("Library/Application Support/com.apple.TCC/TCC.db"), "/Library/Application Support/com.apple.TCC/TCC.db"]
        var rows: [(String, String)] = []
        var anyRead = false
        for db in dbs {
            let r = await Shell.run("/usr/bin/sqlite3", ["-readonly", "-separator", "\t", db,
                                                         "select service, client from access where auth_value = 2"])
            guard r.code == 0 else { continue }
            anyRead = true
            rows += r.out.split(separator: "\n").compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
                return parts.count == 2 ? (parts[0], parts[1]) : nil
            }
        }
        readable = anyRead
        groups = Self.services.map { svc, title, icon, anchor in
            var seen = Set<String>()
            let apps = rows.filter { $0.0 == svc }.compactMap { _, client -> (String, String?)? in
                let resolved = Self.resolve(client)
                return seen.insert(resolved.0).inserted ? resolved : nil
            }.sorted { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
            return PermissionGroup(title: title, icon: icon, anchor: anchor, apps: apps)
        }
        if anyRead {
            // Show filled groups first, empty ones are noise.
            groups = groups.filter { !$0.apps.isEmpty }
        }
        busy = false
    }

    /// Bundle ID or path → readable name and app path (for the icon).
    private static func resolve(_ client: String) -> (String, String?) {
        if client.hasPrefix("/") {
            let u = URL(fileURLWithPath: client)
            if let r = client.range(of: ".app/") {
                let app = String(client[..<r.lowerBound]) + ".app"
                return (URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent, app)
            }
            return (u.lastPathComponent, nil)
        }
        if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: client) {
            let name = FileManager.default.displayName(atPath: u.path).replacingOccurrences(of: ".app", with: "")
            return (name, u.path)
        }
        return (client, nil)
    }
}

// MARK: - Background items

struct BackgroundToolView: View {
    @ObservedObject var m = SecurityModel.shared
    @State private var pending: AutostartItem?

    var body: some View {
        VStack(spacing: 0) {
            Text("Diese Dienste starten automatisch im Hintergrund. Die meisten gehören zu installierten Programmen und sind in Ordnung. Rot oder orange markierte bitte genauer ansehen.")
                .foregroundStyle(.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            if m.scanning && m.autostart.isEmpty {
                ProgressView("Wird geprüft …").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if m.autostart.isEmpty {
                ContentUnavailableView("Keine Hintergrunddienste", systemImage: "checkmark.circle")
            } else {
                List(m.autostart.sorted { $0.level > $1.level }) { a in
                    HStack(alignment: .top, spacing: 10) {
                        LevelIcon(level: a.level)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.label).font(.headline)
                            Text(a.program.map(Fmt.path) ?? "–").font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                            Text("\(a.scope) · \(a.note)").font(.caption)
                        }
                        Spacer()
                        Button { reveal(a.plist) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless).help("Im Finder zeigen")
                        Button("Deaktivieren …") { pending = a }
                    }
                    .padding(.vertical, 2)
                }
            }
            Footer {
                if let msg = m.message { Text(msg).foregroundStyle(.secondary) }
                Spacer()
                if m.scanning { ProgressView().controlSize(.small) }
                Button("Anmeldeobjekte in den Systemeinstellungen …") { SettingsPane.open(SettingsPane.loginItems) }
                Button("Neu prüfen") { Task { await m.scan() } }.disabled(m.scanning)
            }
        }
        .task { if m.lastScan == nil { await m.scan() } }
        .confirmationDialog("Autostart-Eintrag deaktivieren?",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
                            presenting: pending) { a in
            Button("„\(a.label)“ deaktivieren", role: .destructive) { Task { await m.remove(a) } }
        } message: { _ in
            Text("Der Eintrag wird gestoppt und in den Papierkorb gelegt. Das Programm selbst bleibt erhalten. Für Systemdienste fragt macOS nach deinem Passwort.")
        }
    }
}
