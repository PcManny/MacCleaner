import SwiftUI

/// The small tools that open in their own window (sheet) from "Meine Tools".
enum ToolSheet: String, Identifiable {
    case downloads, mail, systemJunk, aiJunk, trash, timeMachine, screenClean, permissions, background
    var id: String { rawValue }
}

/// One tile on the "Meine Tools" page.
struct Tool: Identifiable {
    enum Action { case page(Page, mode: Int), sheet(ToolSheet), url(String) }
    let id: String
    let title: String
    let detail: String
    let icon: String
    let color: Color
    let button: String
    let action: Action

    static let all: [Tool] = [
        Tool(id: "screen", title: "Bildschirm putzen",
             detail: "Schwarzer Bildschirm, Tastatur und Maus gesperrt – so kannst du Bildschirm und Tastatur in Ruhe abwischen.",
             icon: "sparkles.tv", color: .pink, button: "Öffnen", action: .sheet(.screenClean)),
        Tool(id: "ai", title: "KI-Müll",
             detail: "Caches, Protokolle und heruntergeladene Modelle von KI-Programmen wie ChatGPT, Claude oder Ollama.",
             icon: "brain", color: .green, button: "Scannen", action: .sheet(.aiJunk)),
        Tool(id: "tm", title: "Time-Machine-Schnappschüsse",
             detail: "Lokale Schnappschüsse von Time Machine anzeigen und bei Bedarf entfernen.",
             icon: "clock.arrow.circlepath", color: .orange, button: "Scannen", action: .sheet(.timeMachine)),
        Tool(id: "perm", title: "Programm-Berechtigungen",
             detail: "Welche Programme dürfen auf Kamera, Mikrofon, Bildschirm oder alle Dateien zugreifen?",
             icon: "hand.raised.fill", color: .purple, button: "Anzeigen", action: .sheet(.permissions)),
        Tool(id: "dup", title: "Duplikatscanner",
             detail: "Doppelte Dateien in einem Ordner finden und überzählige Kopien entfernen.",
             icon: "doc.on.doc", color: .teal, button: "Scannen", action: .page(.space, mode: 2)),
        Tool(id: "big", title: "Große und alte Dateien",
             detail: "Große Dateien finden, die viel Platz belegen.",
             icon: "doc.badge.ellipsis", color: .cyan, button: "Scannen", action: .page(.space, mode: 1)),
        Tool(id: "folders", title: "Ordnergrößen",
             detail: "Sehen, welche Ordner am meisten Speicher belegen – Ebene für Ebene.",
             icon: "chart.pie", color: .orange, button: "Öffnen", action: .page(.space, mode: 0)),
        Tool(id: "downloads", title: "Downloads",
             detail: "Den Download-Ordner durchsehen und nicht mehr Benötigtes entfernen.",
             icon: "arrow.down.circle", color: Brand.blue, button: "Scannen", action: .sheet(.downloads)),
        Tool(id: "trash", title: "Papierkorb",
             detail: "Sehen, wie viel im Papierkorb liegt, und ihn leeren.",
             icon: "trash", color: .gray, button: "Scannen", action: .sheet(.trash)),
        Tool(id: "mail", title: "Mail-Anhänge",
             detail: "Von Mail gespeicherte Kopien von Anhängen. Die Anhänge bleiben in den E-Mails erhalten.",
             icon: "paperclip", color: .blue, button: "Scannen", action: .sheet(.mail)),
        Tool(id: "system", title: "Systemreste",
             detail: "Programm-Caches, Protokolle und Xcode-Zwischenstände, die unnötig Platz belegen.",
             icon: "gearshape.2", color: .green, button: "Scannen", action: .sheet(.systemJunk)),
        Tool(id: "uninstall", title: "Deinstallation",
             detail: "Programme samt allen zugehörigen Dateien entfernen.",
             icon: "xmark.app", color: .red, button: "Öffnen", action: .page(.uninstall, mode: 0)),
        Tool(id: "leftovers", title: "Programmreste",
             detail: "Reste von Programmen finden, die schon gelöscht sind.",
             icon: "puzzlepiece.extension", color: .indigo, button: "Scannen", action: .page(.uninstall, mode: 1)),
        Tool(id: "login", title: "Anmeldeobjekte",
             detail: "Programme, die beim Start des Mac automatisch öffnen – in den Systemeinstellungen.",
             icon: "power", color: .orange, button: "Öffnen", action: .url(SettingsPane.loginItems)),
        Tool(id: "background", title: "Hintergrundobjekte",
             detail: "Hintergrunddienste und Helfer prüfen und Unerwünschtes abschalten.",
             icon: "gearshape.arrow.triangle.2.circlepath", color: .brown, button: "Scannen", action: .sheet(.background)),
        Tool(id: "malware", title: "Malware-Suche",
             detail: "Nach Werbeprogrammen, veränderten Programmen und Browser-Erweiterungen suchen.",
             icon: "ladybug", color: .pink, button: "Öffnen", action: .page(.malware, mode: 0)),
        Tool(id: "memory", title: "Arbeitsspeicher",
             detail: "Was den Arbeitsspeicher belegt – mit „Beenden“.",
             icon: "memorychip", color: .teal, button: "Öffnen", action: .page(.memory, mode: 0)),
        Tool(id: "maintenance", title: "Wartungsaufgaben",
             detail: "DNS-Cache, Spotlight, Vorschau-Cache und andere kleine Reparaturen.",
             icon: "wrench.and.screwdriver", color: .brown, button: "Öffnen", action: .page(.maintenance, mode: 0)),
    ]
}

struct MyToolsView: View {
    @State private var search = ""
    @State private var sheet: ToolSheet?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Meine Tools",
                       subtitle: "Schnelle Werkzeuge für bestimmte Aufgaben – mit wenigen Klicks aufräumen, schützen und pflegen.") {
                TextField("Suchen …", text: $search).textFieldStyle(.roundedBorder).frame(width: 200)
            }
            ScrollView { MyToolsGrid(search: search, open: open).padding(20) }
        }
        .sheet(item: $sheet) { s in ToolSheetView(sheet: s) }
    }

    private func open(_ tool: Tool) {
        switch tool.action {
        case .page(let p, let mode):
            Nav.shared.mode[p] = mode
            Nav.shared.page = p
        case .sheet(let s): sheet = s
        case .url(let u): SettingsPane.open(u)
        }
    }
}

/// The tiles (separate from the page so it can also be rendered for previews).
struct MyToolsGrid: View {
    var search = ""
    var open: (Tool) -> Void = { _ in }

    private let columns = [GridItem(.adaptive(minimum: 230), spacing: 16)]
    private var tools: [Tool] {
        let q = search.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? Tool.all
            : Tool.all.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.detail.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        if tools.isEmpty {
            ContentUnavailableView.search(text: search)
        }
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(tools) { tool in tile(tool) }
        }
    }

    private func tile(_ tool: Tool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            IconTile(symbol: tool.icon, color: tool.color, size: 44)
            Text(tool.title).font(.headline)
            Text(tool.detail).font(.callout).foregroundStyle(.secondary)
                .lineLimit(4, reservesSpace: true)
            HStack {
                Spacer()
                Button(tool.button) { open(tool) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [tool.color.opacity(0.10), tool.color.opacity(0.02)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open(tool) }
    }
}
