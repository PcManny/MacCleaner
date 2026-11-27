import SwiftUI

struct OverviewView: View {
    @ObservedObject var disk = DiskModel.shared
    @ObservedObject var clean = CleanupModel.shared
    @ObservedObject var sec = SecurityModel.shared
    @ObservedObject var mal = MalwareModel.shared
    @ObservedObject var mem = MemoryModel.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Übersicht", subtitle: "Dein Mac auf einen Blick.") { EmptyView() }
                    .padding(.horizontal, -20)

                Card {
                    HStack {
                        Label("Macintosh HD", systemImage: "internaldrive").font(.headline)
                        Spacer()
                        Text("\(Fmt.bytes(disk.free)) frei").font(.headline)
                    }
                    UsageBar(fraction: disk.usedFraction).frame(height: 12)
                    Text("\(Fmt.bytes(disk.used)) von \(Fmt.bytes(disk.total)) belegt (\(Int(disk.usedFraction * 100)) %)")
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        Label("Aufräumen", systemImage: "sparkles").font(.headline)
                        if clean.scanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(Fmt.bytes(clean.selectedTotal)).font(.system(size: 30, weight: .semibold))
                            Text("können sicher entfernt werden").foregroundStyle(.secondary)
                        }
                        Button("Ansehen") { Nav.shared.page = .cleanup }
                    }
                    Card {
                        Label("Sicherheit", systemImage: "lock.shield").font(.headline)
                        if sec.scanning && sec.lastScan == nil {
                            ProgressView().controlSize(.small)
                        } else {
                            HStack {
                                LevelIcon(level: sec.issueCount == 0 ? .ok : sec.worst)
                                Text(sec.statusText).font(.title2.weight(.semibold))
                            }
                            Text(sec.lastScan.map { "Geprüft: \(Fmt.date($0))" } ?? "").foregroundStyle(.secondary)
                        }
                        Button("Details") { Nav.shared.page = .security }
                    }
                    Card {
                        Label("Speicher", systemImage: "chart.pie").font(.headline)
                        Text("Große Ordner, große Dateien und doppelte Dateien finden.").foregroundStyle(.secondary)
                        Button("Speicherfresser") { Nav.shared.page = .space }
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    Card {
                        Label("Malware-Suche", systemImage: "ladybug").font(.headline)
                        HStack {
                            LevelIcon(level: mal.lastScan == nil ? .info : (mal.problems.isEmpty ? .ok : .danger))
                            Text(mal.statusText).font(.title2.weight(.semibold))
                        }
                        Text(mal.lastScan.map { "Geprüft: \(Fmt.date($0))" } ?? "Schadsoftware, Werbeprogramme, gecrackte Programme")
                            .foregroundStyle(.secondary)
                        Button(mal.lastScan == nil ? "Jetzt prüfen" : "Details") { Nav.shared.page = .malware }
                    }
                    Card {
                        Label("Arbeitsspeicher", systemImage: "memorychip").font(.headline)
                        HStack {
                            LevelIcon(level: mem.stats.pressure.level)
                            Text(mem.stats.pressure.text).font(.title2.weight(.semibold))
                        }
                        Text("\(Fmt.bytes(mem.stats.used)) von \(Fmt.bytes(mem.stats.total)) in Gebrauch").foregroundStyle(.secondary)
                        Button("Details") { Nav.shared.page = .memory }
                    }
                }
                if !sec.newItems.isEmpty {
                    Card {
                        Label("\(sec.newItems.count) neue Autostart-Einträge seit der letzten Prüfung",
                              systemImage: "exclamationmark.shield.fill").foregroundStyle(.orange).font(.headline)
                        Button("Jetzt prüfen") { Nav.shared.page = .security }
                    }
                }
            }
            .padding(20)
        }
        .task {
            mem.stats = MemoryStats.snapshot()
            if clean.lastScan == nil { await clean.scan() }
            if sec.lastScan == nil { await sec.scan() }
        }
    }
}

struct CleanupView: View {
    @ObservedObject var m = CleanupModel.shared
    @State private var confirm = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Aufräumen",
                       subtitle: "Alles wird zuerst in den Papierkorb gelegt. Platz wird frei, sobald der Papierkorb geleert ist.") {
                Button { Task { await m.scan() } } label: { Label("Neu prüfen", systemImage: "arrow.clockwise") }
                    .disabled(m.scanning || m.cleaning)
            }
            List {
                ForEach($m.categories) { $c in CategoryRow(c: $c) }
            }
            Footer {
                if let msg = m.message { Text(msg).foregroundStyle(.secondary).lineLimit(2) }
                if m.needsFullDiskAccess {
                    Button("So geht’s …") { Nav.shared.page = .settings }
                }
                Spacer()
                if m.scanning || m.cleaning { ProgressView().controlSize(.small) }
                Text("Ausgewählt: \(Fmt.bytes(m.selectedTotal))").bold()
                Button("Aufräumen …") { confirm = true }
                    .buttonStyle(.borderedProminent)
                    .disabled((m.selectedTotal == 0 && !m.trashSelected) || m.scanning || m.cleaning)
            }
        }
        .task { if m.lastScan == nil { await m.scan() } }
        .confirmationDialog("Ausgewähltes aufräumen?", isPresented: $confirm) {
            Button(m.trashSelected ? "Aufräumen und Papierkorb leeren" : "In den Papierkorb legen",
                   role: m.trashSelected ? .destructive : nil) {
                Task { await m.clean() }
            }
        } message: {
            Text(m.trashSelected
                 ? "\(Fmt.bytes(m.selectedTotal)) werden entfernt und der Papierkorb wird endgültig geleert. Das lässt sich nicht rückgängig machen."
                 : "\(Fmt.bytes(m.selectedTotal)) werden in den Papierkorb gelegt. Du kannst sie von dort zurückholen.")
        }
    }
}

struct CategoryRow: View {
    @Binding var c: CleanCategory
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: $c.selected).toggleStyle(.checkbox).labelsHidden().padding(.top, 4)
                Image(systemName: c.icon).font(.title2).frame(width: 30).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.name).font(.headline)
                    Text(c.detail).font(.callout).foregroundStyle(.secondary)
                    if c.noAccess {
                        Button("Kein Zugriff – Festplattenvollzugriff erlauben …") { SettingsPane.open(SettingsPane.fullDisk) }
                            .buttonStyle(.link).font(.callout)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.bytes(c.kind == .emptyTrash ? c.total : c.selectedSize)).font(.headline.monospacedDigit())
                    if !c.items.isEmpty && c.kind == .moveToTrash {
                        Button(expanded ? "Ausblenden" : "\(c.items.count) Einträge") { expanded.toggle() }
                            .buttonStyle(.link).font(.caption)
                    }
                }
            }
            if expanded {
                ForEach(c.items.prefix(200)) { item in
                    HStack {
                        Toggle("", isOn: Binding(
                            get: { !c.excluded.contains(item.id) },
                            set: { on in if on { c.excluded.remove(item.id) } else { c.excluded.insert(item.id) } }
                        )).toggleStyle(.checkbox).labelsHidden()
                        Text(item.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Fmt.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                        Button { reveal(item.url) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless).help("Im Finder zeigen")
                    }
                    .font(.callout)
                    .padding(.leading, 76)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

struct UninstallView: View {
    @ObservedObject var m = UninstallModel.shared
    @State private var mode = 0
    @State private var confirm = false
    @State private var confirmOrphans = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Programme entfernen",
                       subtitle: "Entfernt ein Programm samt Einstellungen, Caches und Hintergrunddiensten.") {
                Picker("", selection: $mode) {
                    Text("Programme").tag(0)
                    Text("Reste ohne Programm").tag(1)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 300)
            }
            if mode == 0 { appsPane } else { orphansPane }
        }
        .task { if m.apps.isEmpty { await m.loadApps() } }
    }

    private var appsPane: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Suchen", text: $m.search).textFieldStyle(.roundedBorder)
                    Picker("", selection: $m.sortBySize) {
                        Text("A–Z").tag(false)
                        Text("Größe").tag(true)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 110)
                }
                .padding(.horizontal, 8).padding(.top, 8)
                Text("Mehrere Programme: Kästchen ankreuzen")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.vertical, 4)
                List(m.filtered, selection: Binding(get: { m.selection }, set: { ids in Task { await m.select(ids) } })) { app in
                    HStack {
                        Toggle("", isOn: Binding(get: { m.selection.contains(app.id) },
                                                 set: { _ in Task { await m.toggle(app.id) } }))
                            .toggleStyle(.checkbox).labelsHidden()
                            .help("Ankreuzen, um mehrere Programme auf einmal zu entfernen")
                        Image(nsImage: appIcon(app.url.path)).resizable().frame(width: 24, height: 24)
                        Text(app.name).lineLimit(1)
                        Spacer()
                        Text(m.sizes[app.id].map(Fmt.bytes) ?? "…").foregroundStyle(.secondary).monospacedDigit()
                    }
                    .tag(app.id)
                }
            }
            .frame(minWidth: 300, idealWidth: 340, maxWidth: 460)
            detail.frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder private var detail: some View {
        let chosen = m.selectedApps
        if !chosen.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                if let app = m.selectedApp {
                    HStack(spacing: 14) {
                        Image(nsImage: appIcon(app.url.path)).resizable().frame(width: 60, height: 60)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.name).font(.title2.bold())
                            Text(app.bundleID ?? "ohne Kennung").foregroundStyle(.secondary)
                            Text(app.url.path).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("\(chosen.count) Programme ausgewählt").font(.title2.bold())
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(chosen) { app in
                                VStack(spacing: 4) {
                                    Image(nsImage: appIcon(app.url.path)).resizable().frame(width: 44, height: 44)
                                    Text(app.name).font(.caption).lineLimit(1).frame(maxWidth: 90)
                                }
                            }
                        }
                    }
                }
                Text("Gefundene Reste").font(.headline)
                if m.busy {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if m.leftovers.isEmpty {
                    Text("Keine weiteren Dateien gefunden.").foregroundStyle(.secondary)
                    Spacer()
                } else {
                    List { ForEach($m.leftovers) { $l in LeftoverRow(item: $l) } }
                }
                HStack {
                    if let msg = m.message { Text(msg).foregroundStyle(.secondary) }
                    Spacer()
                    Text("Gesamt: \(Fmt.bytes(m.uninstallTotal))").bold()
                    Button(chosen.count == 1 ? "Deinstallieren …" : "\(chosen.count) Programme deinstallieren …", role: .destructive) { confirm = true }
                        .buttonStyle(.borderedProminent).tint(.red).disabled(m.busy)
                }
            }
            .padding(16)
            .confirmationDialog(chosen.count == 1 ? "\(chosen[0].name) deinstallieren?" : "\(chosen.count) Programme deinstallieren?",
                                isPresented: $confirm) {
                Button("In den Papierkorb legen", role: .destructive) { Task { await m.uninstall() } }
            } message: {
                Text((chosen.count == 1 ? "Das Programm" : chosen.map(\.name).joined(separator: ", "))
                     + " und \(m.leftovers.filter(\.selected).count) ausgewählte Reste werden in den Papierkorb gelegt. Laufende Programme werden vorher beendet. Für Systemdateien fragt macOS nach deinem Passwort.")
            }
        } else {
            VStack {
                ContentUnavailableView("Programm auswählen", systemImage: "app.dashed",
                                       description: Text("Wähle links ein Programm aus – oder kreuze mehrere an –, um sie samt Resten zu entfernen."))
                if let msg = m.message { Text(msg).foregroundStyle(.secondary).padding() }
            }
        }
    }

    private var orphansPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Diese Dateien gehören vermutlich zu Programmen, die nicht mehr installiert sind. Bitte vor dem Entfernen kurz prüfen – im Zweifel nicht auswählen.")
                .foregroundStyle(.secondary).padding(.horizontal, 20).padding(.bottom, 8)
            if m.orphanBusy {
                ProgressView("Suche läuft …").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !m.orphansScanned {
                ContentUnavailableView {
                    Label("Reste suchen", systemImage: "magnifyingglass")
                } actions: {
                    Button("Jetzt suchen") { Task { await m.scanOrphans() } }.buttonStyle(.borderedProminent)
                }
            } else if m.orphans.isEmpty {
                ContentUnavailableView("Keine Reste gefunden", systemImage: "checkmark.circle")
            } else {
                List { ForEach($m.orphans) { $o in LeftoverRow(item: $o) } }
            }
            Footer {
                if let msg = m.message { Text(msg).foregroundStyle(.secondary) }
                Spacer()
                Button("Neu suchen") { Task { await m.scanOrphans() } }.disabled(m.orphanBusy)
                Text("Ausgewählt: \(Fmt.bytes(m.orphanTotal))").bold()
                Button("Entfernen …") { confirmOrphans = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(m.orphanTotal == 0 && !m.orphans.contains(where: \.selected))
            }
        }
        .confirmationDialog("Ausgewählte Reste entfernen?", isPresented: $confirmOrphans) {
            Button("In den Papierkorb legen", role: .destructive) { Task { await m.removeOrphans() } }
        } message: {
            Text("\(m.orphans.filter(\.selected).count) Einträge werden in den Papierkorb gelegt.")
        }
    }
}
