import SwiftUI

struct OverviewView: View {
    @ObservedObject var disk = DiskModel.shared
    @ObservedObject var clean = CleanupModel.shared
    @ObservedObject var sec = SecurityModel.shared
    @ObservedObject var mal = MalwareModel.shared
    @ObservedObject var mem = MemoryModel.shared
    @State private var confirmQuick = false
    @State private var checking = false
    @State private var checked = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Übersicht", subtitle: "Dein Mac auf einen Blick.") { EmptyView() }
                    .padding(.horizontal, -20)

                quickCleanCard

                Card {
                    HStack {
                        HStack(spacing: 8) {
                            IconTile(symbol: "internaldrive", color: .gray, size: 24)
                            Text("Macintosh HD").font(.headline)
                        }
                        Spacer()
                        Text("\(Fmt.bytes(disk.free)) frei").font(.headline)
                    }
                    UsageBar(fraction: disk.usedFraction).frame(height: 12)
                    Text("\(Fmt.bytes(disk.used)) von \(Fmt.bytes(disk.total)) belegt (\(Int(disk.usedFraction * 100)) %)")
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 16) {
                    Card {
                        CardTitle(title: "Aufräumen", page: .cleanup)
                        if clean.scanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Text(Fmt.bytes(clean.selectedTotal)).font(.system(size: 30, weight: .semibold))
                            Text("können sicher entfernt werden").foregroundStyle(.secondary)
                        }
                        Button("Ansehen") { Nav.shared.page = .cleanup }
                    }
                    Card {
                        CardTitle(title: "Sicherheit", page: .security)
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
                        CardTitle(title: "Speicher", page: .space)
                        Text("Große Ordner, große Dateien und doppelte Dateien finden.").foregroundStyle(.secondary)
                        Button("Speicherfresser") { Nav.shared.page = .space }
                    }
                }
                HStack(alignment: .top, spacing: 16) {
                    Card {
                        CardTitle(title: "Malware-Suche", page: .malware)
                        HStack {
                            LevelIcon(level: mal.lastScan == nil ? .info : (mal.problems.isEmpty ? .ok : .danger))
                            Text(mal.statusText).font(.title2.weight(.semibold))
                        }
                        Text(mal.lastScan.map { "Geprüft: \(Fmt.date($0))" } ?? "Schadsoftware, Werbeprogramme, gecrackte Programme")
                            .foregroundStyle(.secondary)
                        Button(mal.lastScan == nil ? "Jetzt prüfen" : "Details") { Nav.shared.page = .malware }
                    }
                    Card {
                        CardTitle(title: "Arbeitsspeicher", page: .memory)
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
        .confirmationDialog("Alles aufräumen?", isPresented: $confirmQuick) {
            Button("In den Papierkorb legen") { Task { await clean.quickClean(emptyTrash: false) } }
            Button("Aufräumen und Papierkorb leeren", role: .destructive) { Task { await clean.quickClean(emptyTrash: true) } }
        } message: {
            Text("\(clean.safeCategories.map(\.name).joined(separator: ", ")) – zusammen \(Fmt.bytes(clean.safeTotal)). Das wird von den Programmen bei Bedarf neu angelegt.\n\n„Papierkorb leeren“ löscht danach endgültig alles im Papierkorb – auch Dinge, die du selbst hineingelegt hast (\(Fmt.bytes(clean.trashTotal))).")
        }
        .task {
            mem.stats = MemoryStats.snapshot()
            if clean.lastScan == nil { await clean.scan() }
            if sec.lastScan == nil { await sec.scan() }
        }
    }
}

extension OverviewView {
    /// Runs all checks at once, like a "smart care" routine.
    func fullCheck() async {
        checking = true
        mem.stats = MemoryStats.snapshot()
        async let a: Void = clean.scan()
        async let b: Void = sec.scan()
        async let c: Void = mal.scan()
        _ = await (a, b, c)
        checking = false
        withAnimation { checked = true }
    }

    /// Four small results inside the blue card.
    var checkResults: some View {
        HStack(spacing: 8) {
            result("Aufräumen", Fmt.bytes(clean.safeTotal), clean.safeTotal > 0 ? "sparkles" : "checkmark") { Nav.shared.page = .cleanup }
            result("Malware", mal.problems.isEmpty ? "nichts gefunden" : "\(mal.problems.count) Funde",
                   mal.problems.isEmpty ? "checkmark" : "exclamationmark.triangle.fill") { Nav.shared.page = .malware }
            result("Sicherheit", sec.statusText, sec.issueCount == 0 ? "checkmark" : "exclamationmark.triangle.fill") { Nav.shared.page = .security }
            result("Speicher", mem.stats.pressure.text, "memorychip") { Nav.shared.page = .memory }
        }
    }

    private func result(_ title: String, _ value: String, _ icon: String, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: icon).font(.caption.weight(.semibold)).opacity(0.85)
                Text(value).font(.callout.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    /// Big blue card with the one-click cleanup.
    var quickCleanCard: some View {
        HStack(alignment: .center, spacing: 20) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 84, height: 84)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 4) {
                if clean.scanning && clean.lastScan == nil {
                    Text("Dein Mac wird geprüft …").font(.title2.bold())
                    ProgressView().controlSize(.small).tint(.white)
                } else if clean.cleaning {
                    Text("Wird aufgeräumt …").font(.title2.bold())
                    ProgressView().controlSize(.small).tint(.white)
                } else if clean.safeTotal > 0 {
                    Text("\(Fmt.bytes(clean.safeTotal)) können sicher weg").font(.system(size: 26, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Text("Caches, Protokolle und Zwischenstände – werden bei Bedarf neu angelegt.")
                        .opacity(0.85)
                } else {
                    Text("Alles sauber").font(.system(size: 26, weight: .bold))
                    Text("Gerade gibt es nichts Sicheres aufzuräumen.").opacity(0.85)
                }
                if let msg = clean.quickMessage {
                    Label(msg, systemImage: "checkmark.circle.fill").font(.callout.weight(.medium)).padding(.top, 4)
                }
                if checked { checkResults.padding(.top, 8) }
            }
            Spacer(minLength: 10)
            VStack(spacing: 10) {
            Button { Task { await fullCheck() } } label: {
                Label(checking ? "Prüft …" : "Rundum-Check", systemImage: "checkmark.shield")
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.white.opacity(0.18), in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(checking)
            .help("Prüft Aufräumen, Malware, Sicherheit und Arbeitsspeicher auf einmal")
            Button { confirmQuick = true } label: {
                Label("Alles aufräumen", systemImage: "sparkles")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 22).padding(.vertical, 12)
                    .background(Brand.orange.gradient, in: Capsule())
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .disabled(clean.scanning || clean.cleaning || clean.safeTotal == 0)
            .opacity(clean.safeTotal == 0 ? 0.5 : 1)
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(red: 0.25, green: 0.66, blue: 0.96), Brand.blue, Brand.deepBlue], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            Text((m.trashSelected
                 ? "\(Fmt.bytes(m.selectedTotal)) werden entfernt und der Papierkorb wird endgültig geleert. Das lässt sich nicht rückgängig machen."
                 : "\(Fmt.bytes(m.selectedTotal)) werden in den Papierkorb gelegt. Du kannst sie von dort zurückholen.")
                 + "\n\nAngehakt: " + m.categories.filter(\.selected).map(\.name).joined(separator: ", "))
        }
    }
}

/// Eigenes Ankreuzkästchen: ein schlichter Knopf, der bei jedem Klick sicher an/aus schaltet.
struct CheckBox: View {
    @Binding var isOn: Bool
    var size: CGFloat = 16

    var body: some View {
        Button { isOn.toggle() } label: {
            Image(systemName: isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: size))
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: size + 8, height: size + 8)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isOn ? "Abwählen" : "Auswählen")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct CategoryRow: View {
    @Binding var c: CleanCategory
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                CheckBox(isOn: Binding(get: { c.selected }, set: { $c.wrappedValue.setAll($0) }), size: 18).padding(.top, 4)
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
                HStack(spacing: 12) {
                    Button("Alle anhaken") { $c.wrappedValue.setAll(true) }
                    Button("Keine") { $c.wrappedValue.setAll(false) }
                }
                .buttonStyle(.link).font(.caption)
                .padding(.leading, 76)
                ForEach(c.items.prefix(200)) { item in
                    HStack {
                        CheckBox(isOn: Binding(
                            get: { c.isItemOn(item.id) },
                            set: { $c.wrappedValue.setItem(item.id, on: $0) }
                        ), size: 14)
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
    @ObservedObject var nav = Nav.shared
    private var mode: Int { nav.mode[.uninstall] ?? 0 }
    private var modeBinding: Binding<Int> { Binding(get: { nav.mode[.uninstall] ?? 0 }, set: { nav.mode[.uninstall] = $0 }) }
    @State private var confirm = false
    @State private var confirmOrphans = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Programme entfernen",
                       subtitle: "Entfernt ein Programm samt Einstellungen, Caches und Hintergrunddiensten.") {
                Picker("", selection: modeBinding) {
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
