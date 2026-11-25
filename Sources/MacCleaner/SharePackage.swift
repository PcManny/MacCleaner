import Foundation

/// Builds a ZIP on the Desktop with the app and the "Bitte zuerst lesen" guide,
/// so the hint about the first-start warning travels with the app.
enum SharePackage {
    enum Outcome { case success(URL), failure(String) }

    static func create() async -> Outcome {
        guard let guide = Bundle.main.url(forResource: "BitteZuerstLesen", withExtension: "html") else {
            return .failure("Die Anleitung fehlt in der App. Bitte MacCleaner mit build.sh neu bauen.")
        }
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("MacCleaner")
        let desktop = home.appendingPathComponent("Desktop")
        var zip = desktop.appendingPathComponent("MacCleaner.zip")
        if fm.fileExists(atPath: zip.path) {
            let stamp = Date().formatted(.iso8601.year().month().day())
            zip = desktop.appendingPathComponent("MacCleaner \(stamp) \(Int.random(in: 100...999)).zip")
        }
        do {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            try fm.copyItem(at: Bundle.main.bundleURL, to: staging.appendingPathComponent("MacCleaner.app"))
            try fm.copyItem(at: guide, to: staging.appendingPathComponent("Bitte zuerst lesen.html"))
        } catch {
            return .failure("Paket konnte nicht vorbereitet werden: \(error.localizedDescription)")
        }
        let r = await Shell.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", staging.path, zip.path])
        try? fm.removeItem(at: staging.deletingLastPathComponent())
        return r.code == 0 ? .success(zip) : .failure("ZIP konnte nicht auf dem Schreibtisch angelegt werden.")
    }
}
