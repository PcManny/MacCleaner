import AppKit
import Foundation
import ServiceManagement
import UserNotifications

let home = FileManager.default.homeDirectoryForCurrentUser

// MARK: - Shell

enum Shell {
    /// Runs a program and returns stdout and the exit code. stderr is discarded.
    static func run(_ launchPath: String, _ args: [String]) async -> (out: String, code: Int32) {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: launchPath)
                p.arguments = args
                // UTF-8, otherwise tools like du print umlauts in file names as "?".
                var env = ProcessInfo.processInfo.environment
                env["LC_ALL"] = "en_US.UTF-8"
                p.environment = env
                let pipe = Pipe()
                p.standardOutput = pipe
                p.standardError = FileHandle.nullDevice
                do { try p.run() } catch {
                    cont.resume(returning: ("", -1))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (String(decoding: data, as: UTF8.self), p.terminationStatus))
            }
        }
    }

    /// Runs a command line in zsh (without user profile) and returns stdout.
    static func sh(_ command: String) async -> String {
        await run("/bin/zsh", ["-f", "-c", command]).out
    }

    /// Runs a command line with administrator rights. macOS shows its own password dialog.
    static func admin(_ command: String) async -> Bool {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"
        return await run("/usr/bin/osascript", ["-e", script]).code == 0
    }

    /// Like `admin`, but returns the command's output (stdout of the shell script).
    static func adminOutput(_ command: String) async -> (out: String, code: Int32) {
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return await run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    }

    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Formatting

enum Fmt {
    static func bytes(_ b: Int64) -> String {
        // macOS would write "Zero KB" here; a plain number reads better.
        if b <= 0 { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: b, countStyle: .file)
    }

    static func gigabytes(_ b: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useGB]
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: b)
    }

    static func date(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .shortened)
    }

    static func path(_ p: String) -> String {
        p.hasPrefix(home.path) ? "~" + p.dropFirst(home.path.count) : p
    }
}

// MARK: - File system helpers

enum FS {
    static func h(_ relative: String) -> String {
        home.appendingPathComponent(relative).path
    }

    /// Children of a folder. Returns nil when the folder exists but cannot be read (missing permission).
    static func children(_ path: String, exclude: (String) -> Bool = { _ in false }) -> [URL]? {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return FileManager.default.fileExists(atPath: path) ? nil : []
        }
        return names
            .filter { $0 != ".DS_Store" && $0 != ".localized" && !exclude($0) }
            .map { URL(fileURLWithPath: path).appendingPathComponent($0) }
    }

    static func existing(_ paths: [String]) -> [URL] {
        paths.filter { FileManager.default.fileExists(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}

enum DiskUsage {
    /// Allocated size in bytes for each path, keyed by path (uses du).
    static func sizes(_ paths: [String]) async -> [String: Int64] {
        var result: [String: Int64] = [:]
        var start = 0
        while start < paths.count {
            let chunk = Array(paths[start..<min(start + 300, paths.count)])
            start += 300
            let out = await Shell.run("/usr/bin/du", ["-skx"] + chunk).out
            for line in out.split(separator: "\n") {
                guard let tab = line.firstIndex(of: "\t"), let kb = Int64(line[..<tab]) else { continue }
                result[String(line[line.index(after: tab)...])] = kb * 1024
            }
        }
        return result
    }
}

// MARK: - Moving things to the Trash

enum Remover {
    /// Moves items to the Trash. Stops launchd jobs first. Asks for the admin password only
    /// when an item cannot be moved with normal rights. Returns nil on success, else an error text.
    static func moveToTrash(_ urls: [URL]) async -> String? {
        var adminCommands: [String] = []

        for u in urls where u.pathExtension == "plist" {
            if u.path.hasPrefix("/Library/LaunchDaemons/") {
                adminCommands.append("launchctl bootout system \(Shell.quote(u.path)) 2>/dev/null || true")
            } else if u.path.contains("/LaunchAgents/") {
                _ = await Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", u.path])
            }
        }

        let failed: [URL] = await Task.detached {
            var failed: [URL] = []
            for u in urls where FS.exists(u) {
                do { try FileManager.default.trashItem(at: u, resultingItemURL: nil) } catch { failed.append(u) }
            }
            return failed
        }.value

        let trash = home.appendingPathComponent(".Trash").path
        for u in failed {
            var dest = trash + "/" + u.lastPathComponent
            if FileManager.default.fileExists(atPath: dest) {
                dest += " " + String(UUID().uuidString.prefix(6))
            }
            adminCommands.append("mv -f \(Shell.quote(u.path)) \(Shell.quote(dest))")
        }

        let needsMove = !failed.isEmpty
        guard !adminCommands.isEmpty else { return nil }
        // Only bootouts and no failed moves: still run them, but they cannot fail.
        let ok = await Shell.admin(adminCommands.joined(separator: "; "))
        if ok { return nil }
        return needsMove
            ? "Einige Dateien konnten nicht entfernt werden (abgebrochen oder vom System geschützt)."
            : nil
    }

    enum TrashResult { case done, noAccess, failed([String]) }

    /// Permanently deletes everything in the user's Trash. Needs Full Disk Access to read ~/.Trash.
    /// Locked files and "deny delete" permissions are cleared first; items owned by another user
    /// (e.g. moved there with admin rights) are deleted with admin rights. Problems are written to
    /// ~/Library/Logs/MacCleaner/Papierkorb.log so the cause can be found later.
    static func emptyTrash() async -> TrashResult {
        let trash = home.appendingPathComponent(".Trash").path
        guard let items = FS.children(trash) else { return .noAccess }
        var log: [String] = []
        var failed: [URL] = []
        for u in items {
            if (try? removeItemDetached(u)) != nil { continue }
            // Unlock (uchg), drop ACLs like "everyone deny delete", make writable – then retry.
            let p = u.path
            _ = await Shell.run("/usr/bin/chflags", ["-R", "nouchg", p])
            _ = await Shell.run("/bin/chmod", ["-R", "-N", p])
            _ = await Shell.run("/bin/chmod", ["-R", "u+rwX", p])
            do { try removeItemDetached(u) } catch {
                let ns = error as NSError
                let where_ = (ns.userInfo[NSFilePathErrorKey] as? String) ?? p
                let under = (ns.userInfo[NSUnderlyingErrorKey] as? NSError)?.localizedDescription ?? ""
                log.append("Als Benutzer: \(where_) – \(ns.localizedDescription) \(under)")
                failed.append(u)
            }
        }
        if !failed.isEmpty {
            // As root: report each item that still exists afterwards, with the rm error message.
            let cmd = failed.map { u in
                let q = Shell.quote(u.path)
                return "chflags -R nouchg,noschg \(q) 2>/dev/null; chmod -R -N \(q) 2>/dev/null; rm -rf \(q) 2>&1 | head -3"
            }.joined(separator: "; ")
            let r = await Shell.adminOutput(cmd)
            log.append("Als Admin (Code \(r.code)):\n\(r.out)")
        }
        var left = failed.filter { FileManager.default.fileExists(atPath: $0.path) }
        if !left.isEmpty {
            // Root via osascript has no Full Disk Access, so it cannot look inside ~/.Trash.
            // The Finder can – it also asks for the password for items owned by root.
            let r = await Shell.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"])
            left = left.filter { FileManager.default.fileExists(atPath: $0.path) }
            log.append("Finder (Code \(r.code)) – danach übrig: \(left.count)")
        }
        if !log.isEmpty { writeTrashLog(log + ["Übrig: " + left.map(\.lastPathComponent).joined(separator: ", ")]) }
        return left.isEmpty ? .done : .failed(left.map(\.lastPathComponent))
    }

    private static func removeItemDetached(_ u: URL) throws {
        try FileManager.default.removeItem(at: u)
    }

    private static func writeTrashLog(_ lines: [String]) {
        let dir = home.appendingPathComponent("Library/Logs/MacCleaner")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let text = "=== \(Date().formatted()) ===\n" + lines.joined(separator: "\n") + "\n\n"
        let file = dir.appendingPathComponent("Papierkorb.log")
        if let h = try? FileHandle(forWritingTo: file) {
            h.seekToEndOfFile(); h.write(Data(text.utf8)); try? h.close()
        } else {
            try? text.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    static var hasFullDiskAccess: Bool {
        FS.children(home.appendingPathComponent(".Trash").path) != nil
    }
}

// MARK: - System integration

enum Notify {
    static func request() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func post(_ title: String, _ body: String) {
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        c.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

enum SettingsPane {
    static let sharing = "x-apple.systempreferences:com.apple.Sharing-Settings.extension"
    static let firewall = "x-apple.systempreferences:com.apple.Network-Settings.extension?Firewall"
    static let profiles = "x-apple.systempreferences:com.apple.Profiles-Settings.extension"
    static let loginItems = "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"
    static let privacy = "x-apple.systempreferences:com.apple.preference.security"
    static let screenCapture = privacy + "?Privacy_ScreenCapture"
    static let accessibility = privacy + "?Privacy_Accessibility"
    static let inputMonitoring = privacy + "?Privacy_ListenEvent"
    static let fullDisk = privacy + "?Privacy_AllFiles"
    static let microphone = privacy + "?Privacy_Microphone"
    static let camera = privacy + "?Privacy_Camera"

    static func open(_ s: String) {
        if let u = URL(string: s) { NSWorkspace.shared.open(u) }
    }
}

enum LoginItem {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

enum AppLinks {
    /// Project page on GitHub (issues = bug reports and ideas).
    static let project = "https://github.com/PcManny/MacCleaner"

    /// Private version only: name and e-mail from Kontakt.plist in the app (build.sh adds it
    /// when Resources/Kontakt-privat.plist exists and the build is not --public).
    static let privateContact: (name: String, email: String)? = {
        guard let u = Bundle.main.url(forResource: "Kontakt", withExtension: "plist"),
              let d = NSDictionary(contentsOf: u),
              let name = d["Name"] as? String, let email = d["Email"] as? String else { return nil }
        return (name, email)
    }()
}

func reveal(_ url: URL) {
    NSWorkspace.shared.activateFileViewerSelecting([url])
}

func appIcon(_ path: String) -> NSImage {
    NSWorkspace.shared.icon(forFile: path)
}
