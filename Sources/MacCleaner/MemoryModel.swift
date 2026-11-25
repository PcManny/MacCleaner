import AppKit
import Darwin
import Foundation

/// One app (or background program) and how much memory it uses, like in the Activity Monitor.
struct MemUser: Identifiable {
    let name: String
    let path: String      // the .app bundle, or the program file
    var bytes: Int64
    var processes: Int
    var id: String { path }
    var isApp: Bool { path.hasSuffix(".app") }
}

enum Pressure: Int {
    case normal = 1, warning = 2, critical = 4

    var text: String {
        switch self {
        case .normal: "Alles gut"
        case .warning: "Wird knapp"
        case .critical: "Zu wenig"
        }
    }

    var level: Level {
        switch self {
        case .normal: .ok
        case .warning: .warn
        case .critical: .danger
        }
    }

    var explanation: String {
        switch self {
        case .normal: "Dein Mac hat genug Arbeitsspeicher. Dass er „voll“ aussieht, ist normal: macOS hält Daten auf Vorrat, damit Programme schneller starten."
        case .warning: "Der Arbeitsspeicher wird knapp. Schließe Programme, die du gerade nicht brauchst – unten siehst du, welche am meisten belegen."
        case .critical: "Der Arbeitsspeicher reicht nicht mehr, der Mac wird langsam. Schließe große Programme oder starte den Mac neu."
        }
    }
}

enum MemoryStats {
    struct Snapshot {
        var total: Int64 = 0
        var app: Int64 = 0
        var wired: Int64 = 0
        var compressed: Int64 = 0
        var cached: Int64 = 0
        var free: Int64 = 0
        var swap: Int64 = 0
        var pressure: Pressure = .normal
        var used: Int64 { app + wired + compressed }
    }

    /// Same numbers the Activity Monitor shows under "Arbeitsspeicher".
    static func snapshot() -> Snapshot {
        var s = Snapshot()
        s.total = Int64(ProcessInfo.processInfo.physicalMemory)

        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        if kr == KERN_SUCCESS {
            let page = Int64(vm_kernel_page_size)
            s.app = (Int64(vm.internal_page_count) - Int64(vm.purgeable_count)) * page
            s.wired = Int64(vm.wire_count) * page
            s.compressed = Int64(vm.compressor_page_count) * page
            s.cached = (Int64(vm.external_page_count) + Int64(vm.purgeable_count)) * page
            s.free = Int64(vm.free_count) * page
        }

        var level: Int32 = 1
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 {
            s.pressure = Pressure(rawValue: Int(level)) ?? .normal
        }

        var swap = xsw_usage()
        size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            s.swap = Int64(swap.xsu_used)
        }
        return s
    }

    /// Memory per app (all helper processes of an app added up). Only the user's own processes
    /// can be measured; system services are left out.
    static func topUsers(limit: Int = 15) -> [MemUser] {
        let n = proc_listallpids(nil, 0)
        guard n > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(n) + 50)
        let got = pids.withUnsafeMutableBufferPointer {
            proc_listallpids($0.baseAddress, Int32($0.count * MemoryLayout<pid_t>.size))
        }
        var byKey: [String: MemUser] = [:]
        var pathBuf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        for pid in pids.prefix(Int(max(got, 0))) where pid > 0 {
            var info = rusage_info_v4()
            let r = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                }
            }
            guard r == 0, info.ri_phys_footprint > 0 else { continue }
            guard proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count)) > 0 else { continue }
            let path = String(cString: pathBuf)
            let (key, name) = owner(of: path)
            byKey[key, default: MemUser(name: name, path: key, bytes: 0, processes: 0)].bytes += Int64(info.ri_phys_footprint)
            byKey[key]?.processes += 1
        }
        return byKey.values.sorted { $0.bytes > $1.bytes }.prefix(limit).map { $0 }
    }

    /// "/Applications/Claude.app/Contents/Frameworks/Helper.app/…" belongs to "Claude".
    static func owner(of path: String) -> (key: String, name: String) {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        if let i = parts.firstIndex(where: { $0.hasSuffix(".app") }) {
            let app = parts[...i].joined(separator: "/")
            return (app, String(parts[i].dropLast(4)))
        }
        return (path, URL(fileURLWithPath: path).lastPathComponent)
    }
}

@MainActor
final class MemoryModel: ObservableObject {
    static let shared = MemoryModel()

    @Published var stats = MemoryStats.Snapshot()
    @Published var users: [MemUser] = []
    @Published var purging = false
    @Published var message: String?

    func refresh() {
        stats = MemoryStats.snapshot()
        Task.detached(priority: .utility) {
            let u = MemoryStats.topUsers()
            await MainActor.run { MemoryModel.shared.users = u }
        }
    }

    /// Empties the file cache with the system tool "purge" (needs the admin password).
    func purge() async {
        purging = true
        let before = MemoryStats.snapshot()
        let ok = await Shell.admin("/usr/sbin/purge")
        try? await Task.sleep(for: .seconds(1))
        let after = MemoryStats.snapshot()
        stats = after
        if ok {
            let gained = after.free - before.free
            message = gained > 50_000_000
                ? "\(Fmt.bytes(gained)) Arbeitsspeicher freigegeben."
                : "Erledigt – es war kaum etwas freizugeben."
        } else {
            message = "Abgebrochen."
        }
        purging = false
    }

    /// Asks an app to quit normally (it can still ask to save documents).
    func quit(_ user: MemUser) {
        let apps = NSWorkspace.shared.runningApplications.filter { $0.bundleURL?.path == user.path }
        guard !apps.isEmpty else {
            message = "„\(user.name)“ lässt sich hier nicht beenden."
            return
        }
        apps.forEach { $0.terminate() }
        message = "„\(user.name)“ wird beendet …"
        Task {
            try? await Task.sleep(for: .seconds(2))
            refresh()
        }
    }

    static func canQuit(_ user: MemUser) -> Bool {
        user.isApp && user.path != Bundle.main.bundlePath
            && NSWorkspace.shared.runningApplications.contains {
                $0.bundleURL?.path == user.path && $0.activationPolicy != .prohibited
            }
    }
}
