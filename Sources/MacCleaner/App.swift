import AppKit
import SwiftUI

enum Page: String, CaseIterable, Identifiable, Hashable {
    case overview = "Übersicht"
    case myTools = "Meine Tools"
    case cleanup = "Aufräumen"
    case uninstall = "Programme entfernen"
    case space = "Speicherfresser"
    case memory = "Arbeitsspeicher"
    case security = "Sicherheit"
    case malware = "Malware-Suche"
    case maintenance = "Wartung"
    case settings = "Einstellungen"

    var id: String { rawValue }

    /// Colour of the rounded square behind the sidebar icon (like System Settings).
    var color: Color {
        switch self {
        case .overview: Brand.blue
        case .myTools: .yellow
        case .cleanup: .green
        case .uninstall: .red
        case .space: .orange
        case .memory: .teal
        case .security: .indigo
        case .malware: .pink
        case .maintenance: .brown
        case .settings: .gray
        }
    }

    var icon: String {
        switch self {
        case .overview: "gauge.with.dots.needle.33percent"
        case .myTools: "star.fill"
        case .cleanup: "sparkles"
        case .uninstall: "trash"
        case .space: "chart.pie"
        case .memory: "memorychip"
        case .security: "lock.shield"
        case .malware: "ladybug"
        case .maintenance: "wrench.and.screwdriver"
        case .settings: "gearshape"
        }
    }
}

@MainActor
final class Nav: ObservableObject {
    static let shared = Nav()
    @Published var page: Page? = .overview
    /// Which tab a page opens on (e.g. Speicherfresser → Duplikate), set by "Meine Tools".
    @Published var mode: [Page: Int] = [:]
    var openWindow: (() -> Void)?

    func show(_ p: Page) {
        page = p
        openWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
            // Developer aid: render the overview card and sidebar into a PNG.
            let out = CommandLine.arguments[i + 1]
            Task { @MainActor in await Snapshot.write(to: out); exit(0) }
            return
        }
        if CommandLine.arguments.contains("--selftest") {
            Task { await SelfTest.run(); exit(0) }
            return
        }
        Task { @MainActor in
            DiskModel.shared.start()
            Notify.request()
            SecurityModel.shared.startMonitoring()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        Task { @MainActor in Nav.shared.show(Nav.shared.page ?? .overview) }
        return true
    }
}

@main
struct MacCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("MacCleaner", id: "main") {
            MainView()
                .frame(minWidth: 960, minHeight: 640)
        }
        .defaultLaunchBehavior(.suppressed)

        MenuBarExtra {
            MenuPopover()
        } label: {
            MenuLabel()
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu bar

struct MenuLabel: View {
    @ObservedObject var sec = SecurityModel.shared
    @Environment(\.openWindow) var openWindow

    var body: some View {
        Group {
            if sec.newItems.isEmpty {
                Image(nsImage: MenuBarIcon.image)
            } else {
                Image(systemName: "exclamationmark.shield.fill")
            }
        }
        .onAppear {
            Nav.shared.openWindow = { openWindow(id: "main") }
            if !UserDefaults.standard.bool(forKey: "didLaunch") {
                UserDefaults.standard.set(true, forKey: "didLaunch")
                Nav.shared.show(.overview)
            }
        }
    }
}

struct MenuPopover: View {
    @ObservedObject var disk = DiskModel.shared
    @ObservedObject var sec = SecurityModel.shared
    @ObservedObject var clean = CleanupModel.shared
    @ObservedObject var mem = MemoryModel.shared
    @ObservedObject var mal = MalwareModel.shared
    @Environment(\.openWindow) var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label { Text("MacCleaner") } icon: { Image(nsImage: MenuBarIcon.image).foregroundStyle(Brand.blue) }
                    .font(.headline)
                Spacer()
                Text("\(Fmt.bytes(disk.free)) frei").foregroundStyle(.secondary)
            }
            UsageBar(fraction: disk.usedFraction).frame(height: 8)
            Text("\(Fmt.bytes(disk.used)) von \(Fmt.bytes(disk.total)) belegt")
                .font(.caption).foregroundStyle(.secondary)

            Divider()

            if !sec.newItems.isEmpty {
                Button { Nav.shared.show(.security) } label: {
                    Label("\(sec.newItems.count) neue Autostart-Einträge prüfen", systemImage: "exclamationmark.shield.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
            row("lock.shield", "Sicherheit", sec.statusText, sec.lastScan == nil ? .secondary : sec.worst.color) {
                Nav.shared.show(.security)
            }
            row("ladybug", "Malware", mal.statusText,
                mal.lastScan == nil ? .secondary : (mal.problems.isEmpty ? .green : .red)) {
                Nav.shared.show(.malware)
            }
            row("memorychip", "Arbeitsspeicher", mem.stats.pressure.text, mem.stats.pressure.level.color) {
                Nav.shared.show(.memory)
            }
            row("sparkles", "Aufräumbar", clean.lastScan == nil ? "noch nicht geprüft" : Fmt.bytes(clean.selectedTotal), .primary) {
                Nav.shared.show(.cleanup)
            }
            row("chart.pie", "Speicherfresser", "anzeigen", .secondary) { Nav.shared.show(.space) }
            row("trash", "Programm entfernen", "auswählen", .secondary) { Nav.shared.show(.uninstall) }

            Divider()

            HStack {
                Button("MacCleaner öffnen") { Nav.shared.show(.overview) }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Beenden") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 310)
        .tint(Brand.blue)
        .onAppear {
            Nav.shared.openWindow = { openWindow(id: "main") }
            disk.refresh()
            mem.stats = MemoryStats.snapshot()
        }
    }

    private func row(_ icon: String, _ title: String, _ value: String, _ color: Color,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).frame(width: 18)
                Text(title)
                Spacer()
                Text(value).foregroundStyle(color)
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Main window

struct MainView: View {
    @ObservedObject var nav = Nav.shared
    @ObservedObject var sec = SecurityModel.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.page) {
                ForEach(Page.allCases) { p in
                    NavigationLink(value: p) {
                        Label { Text(p.rawValue) } icon: { IconTile(symbol: p.icon, color: p.color) }
                            .badge(p == .security && sec.issueCount > 0 ? sec.issueCount : 0)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch nav.page ?? .overview {
            case .overview: OverviewView()
            case .myTools: MyToolsView()
            case .cleanup: CleanupView()
            case .uninstall: UninstallView()
            case .space: SpaceView()
            case .memory: MemoryView()
            case .security: SecurityView()
            case .malware: MalwareView()
            case .maintenance: MaintenanceView()
            case .settings: SettingsView()
            }
        }
        .tint(Brand.blue)
    }
}
