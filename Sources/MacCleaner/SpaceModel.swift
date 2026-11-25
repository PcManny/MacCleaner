import CryptoKit
import Foundation

struct SpaceEntry: Identifiable {
    let url: URL
    let size: Int64
    let isDir: Bool
    var modified: Date? = nil
    var id: String { url.path }
}

enum SpaceScanner {
    /// Sizes of everything directly inside a folder (stays on the same volume).
    static func children(of url: URL) async -> [SpaceEntry] {
        // Network/other volumes are skipped so a folder scan never wanders onto a NAS.
        let rootVolume = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        let kids = (FS.children(url.path) ?? []).filter { child in
            let vol = try? child.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
            return rootVolume == nil || vol == nil || vol == rootVolume
        }
        let sizes = await DiskUsage.sizes(kids.map(\.path))
        return kids
            .map { SpaceEntry(url: $0, size: sizes[$0.path] ?? 0, isDir: FS.isDirectory($0.path)) }
            .sorted { $0.size > $1.size }
    }

    static func bigFiles(minBytes: Int64) async -> [SpaceEntry] {
        let out = await Shell.run("/usr/bin/mdfind", ["-onlyin", home.path, "kMDItemFSSize > \(minBytes)"]).out
        return out.split(separator: "\n").compactMap { line -> SpaceEntry? in
            let path = String(line)
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  (attrs[.type] as? FileAttributeType) == .typeRegular,
                  let size = (attrs[.size] as? NSNumber)?.int64Value, size >= minBytes
            else { return nil }
            return SpaceEntry(url: URL(fileURLWithPath: path), size: size, isDir: false,
                              modified: attrs[.modificationDate] as? Date)
        }.sorted { $0.size > $1.size }
    }

    /// Groups of identical files (≥ 1 MB): same size first, then same SHA-256.
    static func duplicates(in folder: URL) -> [[SpaceEntry]] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let en = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { return [] }

        var bySize: [Int64: [URL]] = [:]
        var count = 0
        for case let u as URL in en {
            guard let v = try? u.resourceValues(forKeys: Set(keys)),
                  v.isRegularFile == true, v.isSymbolicLink != true,
                  let s = v.fileSize, s >= 1_000_000
            else { continue }
            bySize[Int64(s), default: []].append(u)
            count += 1
            if count > 300_000 { break }
        }

        var result: [[SpaceEntry]] = []
        for (size, urls) in bySize where urls.count > 1 {
            var byHash: [String: [URL]] = [:]
            for u in urls {
                if let h = hash(u) { byHash[h, default: []].append(u) }
            }
            for (_, group) in byHash where group.count > 1 {
                result.append(group.sorted { $0.path < $1.path }.map { SpaceEntry(url: $0, size: size, isDir: false) })
            }
        }
        return result.sorted { wasted($0) > wasted($1) }
    }

    static func wasted(_ group: [SpaceEntry]) -> Int64 {
        (group.first?.size ?? 0) * Int64(max(group.count - 1, 0))
    }

    private static func hash(_ u: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: u) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let d = try? h.read(upToCount: 4 << 20), !d.isEmpty {
            hasher.update(data: d)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class SpaceModel: ObservableObject {
    static let shared = SpaceModel()

    @Published var current: URL = home
    @Published var entries: [SpaceEntry] = []
    @Published var busy = false
    @Published var bigFiles: [SpaceEntry] = []
    @Published var bigBusy = false
    @Published var bigScanned = false
    @Published var minMB = 500
    @Published var dupFolder: URL = home.appendingPathComponent("Downloads")
    @Published var dupGroups: [[SpaceEntry]] = []
    @Published var dupBusy = false
    @Published var dupScanned = false
    @Published var message: String?
    private var cache: [String: [SpaceEntry]] = [:]

    var wastedTotal: Int64 { dupGroups.reduce(0) { $0 + SpaceScanner.wasted($1) } }

    func open(_ url: URL, force: Bool = false) async {
        current = url
        if !force, let cached = cache[url.path] {
            entries = cached
            return
        }
        busy = true
        entries = []
        let found = await SpaceScanner.children(of: url)
        cache[url.path] = found
        if current == url { entries = found }
        busy = false
    }

    func up() async {
        let parent = current.deletingLastPathComponent()
        await open(parent)
    }

    func scanBig() async {
        bigBusy = true
        bigFiles = await SpaceScanner.bigFiles(minBytes: Int64(minMB) * 1_000_000)
        bigBusy = false
        bigScanned = true
    }

    func scanDuplicates() async {
        dupBusy = true
        let folder = dupFolder
        dupGroups = await Task.detached(priority: .userInitiated) { SpaceScanner.duplicates(in: folder) }.value
        dupBusy = false
        dupScanned = true
    }

    func trash(_ e: SpaceEntry) async {
        if let error = await Remover.moveToTrash([e.url]) {
            message = error
            return
        }
        message = "„\(e.url.lastPathComponent)“ liegt im Papierkorb."
        entries.removeAll { $0.id == e.id }
        bigFiles.removeAll { $0.id == e.id }
        dupGroups = dupGroups.map { $0.filter { $0.id != e.id } }.filter { $0.count > 1 }
        // Parent folder sizes are now outdated.
        cache = cache.filter { !e.url.path.hasPrefix($0.key + "/") && $0.key != current.path }
        cache[current.path] = entries
        DiskModel.shared.refresh()
    }
}
