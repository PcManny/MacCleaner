import AppKit
import SwiftUI

struct SpaceView: View {
    @ObservedObject var m = SpaceModel.shared
    @State private var mode = 0
    @State private var pendingTrash: SpaceEntry?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Speicherfresser", subtitle: "Finde heraus, was deinen Speicher belegt.") {
                Picker("", selection: $mode) {
                    Text("Ordner").tag(0)
                    Text("Große Dateien").tag(1)
                    Text("Duplikate").tag(2)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 340)
            }
            switch mode {
            case 0: folderPane
            case 1: bigPane
            default: dupPane
            }
            if let msg = m.message {
                Footer { Text(msg).foregroundStyle(.secondary); Spacer() }
            }
        }
        .confirmationDialog("In den Papierkorb legen?",
                            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
                            presenting: pendingTrash) { e in
            Button("„\(e.url.lastPathComponent)“ in den Papierkorb", role: .destructive) {
                Task { await m.trash(e) }
            }
        } message: { e in
            Text("\(Fmt.bytes(e.size)) – \(Fmt.path(e.url.path))")
        }
    }

    // MARK: Folders

    private var folderPane: some View {
        VStack(spacing: 0) {
            HStack {
                Button { Task { await m.up() } } label: { Image(systemName: "chevron.left") }
                    .disabled(m.current.path == "/" || m.busy)
                Text(Fmt.path(m.current.path)).font(.headline).lineLimit(1).truncationMode(.head)
                Spacer()
                Button("Ordner wählen …") {
                    if let u = pickFolder(m.current) { Task { await m.open(u) } }
                }
                Button { Task { await m.open(m.current, force: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(m.busy)
            }
            .padding(.horizontal, 20).padding(.bottom, 8)

            if m.busy {
                ProgressView("Größen werden berechnet … bei großen Ordnern kann das eine Minute dauern.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let maxSize = max(m.entries.first?.size ?? 1, 1)
                List(m.entries.prefix(300)) { e in
                    HStack(spacing: 10) {
                        Image(nsImage: appIcon(e.url.path)).resizable().frame(width: 20, height: 20)
                        Text(e.url.lastPathComponent).lineLimit(1).frame(minWidth: 180, alignment: .leading)
                        UsageBar(fraction: Double(e.size) / Double(maxSize)).frame(height: 6)
                        Text(Fmt.bytes(e.size)).monospacedDigit().frame(width: 90, alignment: .trailing)
                        if e.isDir {
                            Button { Task { await m.open(e.url) } } label: { Image(systemName: "chevron.right") }
                                .buttonStyle(.borderless).help("Öffnen")
                        } else {
                            Color.clear.frame(width: 14)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { if e.isDir { Task { await m.open(e.url) } } }
                    .contextMenu { entryMenu(e) }
                }
            }
        }
        .task { if m.entries.isEmpty && !m.busy { await m.open(m.current) } }
    }

    // MARK: Big files

    private var bigPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Dateien im Benutzerordner größer als")
                Picker("", selection: $m.minMB) {
                    Text("100 MB").tag(100)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1000)
                    Text("5 GB").tag(5000)
                }
                .labelsHidden().frame(width: 100)
                Spacer()
                Button("Suchen") { Task { await m.scanBig() } }.buttonStyle(.borderedProminent).disabled(m.bigBusy)
            }
            .padding(.horizontal, 20).padding(.bottom, 8)

            if m.bigBusy {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if m.bigScanned && m.bigFiles.isEmpty {
                ContentUnavailableView("Keine Dateien gefunden", systemImage: "checkmark.circle")
            } else {
                List(m.bigFiles) { e in fileRow(e, detail: e.modified.map { "geändert \(Fmt.date($0))" }) }
            }
        }
        .task { if !m.bigScanned { await m.scanBig() } }
    }

    // MARK: Duplicates

    private var dupPane: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ordner:")
                Text(Fmt.path(m.dupFolder.path)).bold().lineLimit(1).truncationMode(.head)
                Button("Ändern …") { if let u = pickFolder(m.dupFolder) { m.dupFolder = u; m.dupScanned = false; m.dupGroups = [] } }
                Spacer()
                if m.dupScanned && !m.dupGroups.isEmpty {
                    Text("\(m.dupGroups.count) Gruppen · \(Fmt.bytes(m.wastedTotal)) doppelt").foregroundStyle(.secondary)
                }
                Button("Suchen") { Task { await m.scanDuplicates() } }.buttonStyle(.borderedProminent).disabled(m.dupBusy)
            }
            .padding(.horizontal, 20).padding(.bottom, 8)

            if m.dupBusy {
                ProgressView("Dateien werden verglichen …").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !m.dupScanned {
                ContentUnavailableView("Doppelte Dateien finden", systemImage: "doc.on.doc",
                                       description: Text("Vergleicht den Inhalt aller Dateien ab 1 MB im gewählten Ordner. Behalte von jeder Gruppe eine Datei."))
            } else if m.dupGroups.isEmpty {
                ContentUnavailableView("Keine Duplikate gefunden", systemImage: "checkmark.circle")
            } else {
                List {
                    ForEach(Array(m.dupGroups.enumerated()), id: \.offset) { _, group in
                        Section("\(group.count)× \(Fmt.bytes(group[0].size)) – \(group[0].url.lastPathComponent)") {
                            ForEach(group) { e in fileRow(e, detail: nil) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func fileRow(_ e: SpaceEntry, detail: String?) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon(e.url.path)).resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.url.lastPathComponent).lineLimit(1)
                Text(Fmt.path(e.url.deletingLastPathComponent().path) + (detail.map { " · " + $0 } ?? ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(Fmt.bytes(e.size)).monospacedDigit()
            Button { reveal(e.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Im Finder zeigen")
            Button { pendingTrash = e } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("In den Papierkorb")
        }
        .contextMenu { entryMenu(e) }
    }

    @ViewBuilder private func entryMenu(_ e: SpaceEntry) -> some View {
        Button("Im Finder zeigen") { reveal(e.url) }
        Button("In den Papierkorb legen …") { pendingTrash = e }
    }

    private func pickFolder(_ start: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = start
        panel.prompt = "Auswählen"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Security

struct SecurityView: View {
    @ObservedObject var m = SecurityModel.shared
    @State private var pending: AutostartItem?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Sicherheit",
                       subtitle: m.lastScan.map { "Zuletzt geprüft: \(Fmt.date($0)) · Autostart wird alle 5 Minuten überwacht" } ?? "Noch nicht geprüft") {
                HStack {
                    if m.scanning { ProgressView().controlSize(.small) }
                    Button { Task { await m.scan() } } label: { Label("Jetzt prüfen", systemImage: "arrow.clockwise") }
                        .disabled(m.scanning)
                }
            }
            if m.scanning && m.lastScan == nil {
                ProgressView("Dein Mac wird geprüft … das dauert etwa eine halbe Minute.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !m.newItems.isEmpty {
                        Section {
                            ForEach(m.newItems, id: \.self) { p in
                                HStack {
                                    Text(Fmt.path(p))
                                    Spacer()
                                    Button { reveal(URL(fileURLWithPath: p)) } label: { Image(systemName: "magnifyingglass") }
                                        .buttonStyle(.borderless)
                                }
                            }
                            Button("Kenne ich – als bekannt markieren") { m.acceptNew() }
                        } header: {
                            Label("Neue Autostart-Einträge seit der letzten Prüfung", systemImage: "exclamationmark.shield.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    Section("Schutz & Freigaben") {
                        ForEach(m.checks) { c in
                            HStack(alignment: .top, spacing: 10) {
                                LevelIcon(level: c.level)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.title).font(.headline)
                                    Text(c.detail).foregroundStyle(.secondary).textSelection(.enabled)
                                }
                                Spacer()
                                if let pane = c.pane { Button("Einstellungen …") { SettingsPane.open(pane) } }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    Section("Autostart & Hintergrunddienste (\(m.autostart.count))") {
                        ForEach(m.autostart) { a in
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
                    Section("Laufende Programme") {
                        if m.processes.isEmpty {
                            Label("Alle laufenden Programme sind ordnungsgemäß signiert.", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        ForEach(m.processes) { p in
                            HStack(alignment: .top, spacing: 10) {
                                LevelIcon(level: p.level)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(URL(fileURLWithPath: p.path).lastPathComponent).font(.headline)
                                    Text(Fmt.path(p.path)).font(.caption).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                    Text(p.note).font(.caption)
                                }
                                Spacer()
                                Button { reveal(URL(fileURLWithPath: p.path)) } label: { Image(systemName: "magnifyingglass") }
                                    .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            if let msg = m.message { Footer { Text(msg).foregroundStyle(.secondary); Spacer() } }
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

// MARK: - Maintenance

struct MaintenanceView: View {
    @ObservedObject var m = MaintenanceModel.shared

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Wartung", subtitle: "Kleine Reparaturen, wenn etwas hakt. Nichts davon muss regelmäßig laufen.") { EmptyView() }
            List(m.tasks) { t in
                HStack(spacing: 12) {
                    Image(systemName: t.icon).font(.title2).frame(width: 32).foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(t.title).font(.headline)
                            if t.admin {
                                Text("Passwort nötig").font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(.quaternary, in: Capsule())
                            }
                        }
                        Text(t.detail).foregroundStyle(.secondary)
                        if let s = m.status[t.id] { Text(s).font(.caption).foregroundStyle(.green) }
                    }
                    Spacer()
                    if m.running == t.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Ausführen") { Task { await m.run(t) } }.disabled(m.running != nil)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("monitor") private var monitor = true
    @State private var login = LoginItem.enabled
    @State private var loginError: String?

    @State private var fullDiskAccess = Remover.hasFullDiskAccess
    @State private var sharing = false
    @State private var shareResult: String?
    @State private var shareURL: URL?

    private var inApplications: Bool { Bundle.main.bundlePath.hasPrefix("/Applications/") }

    private func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \(Shell.quote(Bundle.main.bundlePath))"]
        try? p.run()
        NSApp.terminate(nil)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Einstellungen", subtitle: "MacCleaner \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")") { EmptyView() }
            Form {
                Section("Allgemein") {
                    Toggle("Beim Anmelden automatisch starten", isOn: $login)
                        .disabled(!inApplications)
                        .onChange(of: login) { _, on in
                            do { try LoginItem.set(on); loginError = nil } catch {
                                loginError = error.localizedDescription
                                login = LoginItem.enabled
                            }
                        }
                    if !inApplications {
                        Text("Dafür muss MacCleaner im Ordner „Programme“ liegen.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let e = loginError { Text(e).font(.caption).foregroundStyle(.red) }
                    Toggle("Neue Autostart-Einträge überwachen und melden", isOn: $monitor)
                }
                Section("Festplattenvollzugriff") {
                    if fullDiskAccess {
                        Label("Erteilt – MacCleaner kann den Papierkorb leeren und alle Bereiche prüfen.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Fehlt – Papierkorb, Mail-Anhänge und iPhone-Backups werden übersprungen.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. Auf „Einstellungen öffnen“ klicken.")
                            Text("2. Unten auf „+“ klicken (ggf. mit Passwort/Touch ID bestätigen).")
                            Text("3. Im Ordner „Programme“ MacCleaner auswählen und „Öffnen“ klicken.")
                            Text("4. Schalter bei MacCleaner einschalten, dann hier „MacCleaner neu starten“.")
                        }
                        .foregroundStyle(.secondary)
                        HStack {
                            Button("Einstellungen öffnen …") { SettingsPane.open(SettingsPane.fullDisk) }
                            Button("Programme-Ordner zeigen") { reveal(URL(fileURLWithPath: Bundle.main.bundlePath)) }
                            Button("MacCleaner neu starten") { relaunch() }
                        }
                    }
                }
                Section("An Familie & Freunde weitergeben") {
                    Text("Erstellt eine ZIP-Datei auf dem Schreibtisch mit MacCleaner und der Anleitung „Bitte zuerst lesen“. Die erklärt, wie man die Warnung beim ersten Öffnen überspringt – die erscheint nämlich, bevor MacCleaner startet. Läuft ab macOS 15 auf Apple-Chip- und Intel-Macs.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Weitergabe-Paket erstellen") {
                            sharing = true
                            shareResult = nil
                            Task {
                                switch await SharePackage.create() {
                                case .success(let url): shareURL = url; shareResult = "Fertig: „\(url.lastPathComponent)“ liegt auf dem Schreibtisch. Per AirDrop, USB-Stick oder E-Mail weitergeben."
                                case .failure(let msg): shareURL = nil; shareResult = msg
                                }
                                sharing = false
                            }
                        }
                        .disabled(sharing)
                        if sharing { ProgressView().controlSize(.small) }
                        Button("Anleitung ansehen") {
                            if let u = Bundle.main.url(forResource: "BitteZuerstLesen", withExtension: "html") { NSWorkspace.shared.open(u) }
                        }
                    }
                    if let r = shareResult {
                        HStack {
                            Text(r).foregroundStyle(shareURL == nil ? .red : .green)
                            if let u = shareURL { Button("Im Finder zeigen") { reveal(u) } }
                        }
                    }
                }
                Section("Weitere Einstellungen") {
                    Button("Anmeldeobjekte öffnen …") { SettingsPane.open(SettingsPane.loginItems) }
                }
                Section("So arbeitet MacCleaner") {
                    Text("MacCleaner löscht nie direkt: Alles landet im Papierkorb, bis du ihn leerst. Es werden keine Daten ins Internet gesendet.")
                        .foregroundStyle(.secondary)
                }
                Section("Fragen, Probleme oder Ideen?") {
                    if let c = AppLinks.privateContact {
                        Text("Schreib einfach eine E-Mail an \(c.name):")
                            .foregroundStyle(.secondary)
                        Link(c.email, destination: URL(string: "mailto:\(c.email)?subject=MacCleaner")!)
                    } else {
                        Text("Frag einfach die Person, von der du MacCleaner bekommen hast – oder melde dich auf GitHub unter „Issues“.")
                            .foregroundStyle(.secondary)
                        Link("MacCleaner auf GitHub", destination: URL(string: AppLinks.project)!)
                        Link("Fehler melden oder Idee vorschlagen", destination: URL(string: AppLinks.project + "/issues")!)
                    }
                }
            }
            .formStyle(.grouped)
            .onAppear { fullDiskAccess = Remover.hasFullDiskAccess }
        }
    }
}
