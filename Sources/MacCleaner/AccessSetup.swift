import AppKit
import SwiftUI

/// Full Disk Access cannot be requested with a system dialog (Apple does not allow it).
/// So MacCleaner does what other cleaners do: it touches a protected file, which makes
/// macOS list MacCleaner under "Festplattenvollzugriff" (switched off), opens that page
/// and watches until the user flips the switch.
@MainActor
final class AccessModel: ObservableObject {
    static let shared = AccessModel()
    @Published var granted = Remover.hasFullDiskAccess
    @Published var showSetup = false
    private var timer: Timer?

    /// Read attempts on protected places – this is what puts MacCleaner into the list.
    nonisolated static func register() {
        let paths = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            FS.h("Library/Safari/Bookmarks.plist"),
            FS.h("Library/Mail"),
            FS.h(".Trash"),
        ]
        for p in paths {
            _ = FileManager.default.contents(atPath: p)
            _ = try? FileManager.default.contentsOfDirectory(atPath: p)
        }
    }

    /// Called once at launch: shows the setup window when access is missing.
    func checkAtLaunch() {
        granted = Remover.hasFullDiskAccess
        guard !granted, Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        Self.register()
        ask()
    }

    func ask() {
        showSetup = true
        Nav.shared.show(Nav.shared.page ?? .overview)
        startWatching()
    }

    func openSettings() {
        Self.register()
        SettingsPane.open(SettingsPane.fullDisk)
        startWatching()
    }

    func startWatching() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in
                let shared = AccessModel.shared
                shared.granted = Remover.hasFullDiskAccess
                if shared.granted || !shared.showSetup { shared.stopWatching() }
            }
        }
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
    }

    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \(Shell.quote(Bundle.main.bundlePath))"]
        try? p.run()
        NSApp.terminate(nil)
    }
}

struct AccessSetupView: View {
    @ObservedObject var m = AccessModel.shared

    var body: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)

            if m.granted {
                Label("Geschafft – Festplattenvollzugriff ist erlaubt!", systemImage: "checkmark.circle.fill")
                    .font(.title2.bold()).foregroundStyle(.green)
                Text("MacCleaner kann jetzt den Papierkorb leeren und alle Bereiche prüfen.")
                    .foregroundStyle(.secondary)
                Button("Weiter") { m.showSetup = false }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            } else {
                Text("Noch ein Schritt: Festplattenvollzugriff erlauben")
                    .font(.title2.bold())
                Text("Damit MacCleaner den Papierkorb leeren und Mail-Anhänge sowie iPhone-Backups finden kann, braucht es diese Erlaubnis. MacCleaner steht schon in der Liste – du musst nur den Schalter einschalten.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 10) {
                    step(1, "Auf „Einstellungen öffnen“ klicken.")
                    step(2, "Den Schalter bei **MacCleaner** einschalten und mit Passwort oder Touch ID bestätigen.")
                    step(3, "Fragt der Mac „Beenden & erneut öffnen“, einfach zustimmen.")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

                Button { m.openSettings() } label: {
                    Label("Einstellungen öffnen", systemImage: "gearshape").frame(minWidth: 200)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.defaultAction)

                HStack(spacing: 10) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable().frame(width: 32, height: 32)
                        .onDrag { NSItemProvider(contentsOf: Bundle.main.bundleURL) ?? NSItemProvider() }
                        .help("In die Liste „Festplattenvollzugriff“ ziehen")
                    Text("Steht MacCleaner nicht in der Liste? Dann dieses Symbol einfach in die Liste ziehen.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack {
                    ProgressView().controlSize(.small)
                    Text("Warte auf die Erlaubnis …").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Neu starten") { AccessModel.relaunch() }
                        .help("Falls der Schalter schon an ist, aber hier noch nichts passiert")
                    Button("Später") { m.showSetup = false }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(28)
        .frame(width: 520)
        .tint(Brand.blue)
        .onAppear { if !m.granted { m.startWatching() } }
        .onDisappear { m.stopWatching() }
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)").font(.callout.bold()).foregroundStyle(.white)
                .frame(width: 22, height: 22).background(Circle().fill(Brand.blue))
            Text(text)
        }
    }
}
