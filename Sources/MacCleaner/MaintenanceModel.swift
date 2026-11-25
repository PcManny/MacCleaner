import Foundation

struct MaintTask: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let admin: Bool
    let command: String
}

@MainActor
final class MaintenanceModel: ObservableObject {
    static let shared = MaintenanceModel()

    @Published var running: String?
    @Published var status: [String: String] = [:]

    let tasks: [MaintTask] = {
        var t = [
            MaintTask(id: "dns", title: "DNS-Cache leeren",
                      detail: "Hilft, wenn Webseiten nicht laden oder nach einem Router-Wechsel falsch aufgelöst werden.",
                      icon: "network", admin: true,
                      command: "dscacheutil -flushcache; killall -HUP mDNSResponder"),
            MaintTask(id: "spotlight", title: "Spotlight neu aufbauen",
                      detail: "Wenn die Suche Dateien nicht findet. Der Neuaufbau läuft danach eine Weile im Hintergrund.",
                      icon: "magnifyingglass", admin: true, command: "mdutil -E /"),
            MaintTask(id: "quicklook", title: "Vorschau-Cache zurücksetzen",
                      detail: "Bei falschen oder fehlenden Vorschaubildern (Leertaste / Symbole im Finder).",
                      icon: "eye", admin: false, command: "qlmanage -r cache; qlmanage -r"),
            MaintTask(id: "launchservices", title: "„Öffnen mit“-Menü bereinigen",
                      detail: "Entfernt doppelte und gelöschte Programme aus dem „Öffnen mit“-Menü.",
                      icon: "list.bullet.rectangle", admin: false,
                      command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user"),
            MaintTask(id: "fonts", title: "Schriften-Cache leeren",
                      detail: "Bei falsch dargestellten Schriften. Danach den Mac neu starten.",
                      icon: "textformat", admin: true, command: "atsutil databases -remove"),
            MaintTask(id: "dock", title: "Dock & Finder neu starten",
                      detail: "Wenn Dock oder Finder hängen oder nicht mehr reagieren.",
                      icon: "dock.rectangle", admin: false, command: "killall Dock; killall Finder"),
        ]
        if FileManager.default.fileExists(atPath: "/usr/sbin/periodic") {
            t.insert(MaintTask(id: "periodic", title: "Wartungsskripte ausführen",
                               detail: "Die täglichen, wöchentlichen und monatlichen Aufräumskripte von macOS.",
                               icon: "calendar.badge.clock", admin: true, command: "periodic daily weekly monthly"),
                     at: 2)
        }
        return t
    }()

    func run(_ task: MaintTask) async {
        running = task.id
        let ok = task.admin
            ? await Shell.admin(task.command)
            : await Shell.run("/bin/zsh", ["-f", "-c", task.command]).code == 0
        status[task.id] = ok
            ? "Erledigt um \(Date().formatted(date: .omitted, time: .shortened))"
            : "Abgebrochen oder fehlgeschlagen"
        running = nil
    }
}
