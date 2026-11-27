import SwiftUI

/// `MacCleaner --snapshot file.png` renders the new overview parts for checking the look.
@MainActor
enum Snapshot {
    /// `--snapshot-access file.png`: the Full Disk Access window (both states side by side).
    static func writeAccess(to path: String) {
        let m = AccessModel.shared
        m.granted = false
        let missing = ImageRenderer(content: AccessSetupView().background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light)).nsImage
        m.granted = true
        let done = ImageRenderer(content: AccessSetupView().background(Color(nsColor: .windowBackgroundColor)).environment(\.colorScheme, .light)).nsImage
        let view = HStack(alignment: .top, spacing: 20) {
            if let missing { Image(nsImage: missing) }
            if let done { Image(nsImage: done) }
        }.padding(20).background(Color.gray.opacity(0.3))
        let r = ImageRenderer(content: view)
        r.scale = 1
        if let img = r.nsImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }

    static func write(to path: String) async {
        await CleanupModel.shared.scan()
        let view = HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Page.allCases) { p in
                    HStack(spacing: 8) { IconTile(symbol: p.icon, color: p.color); Text(p.rawValue) }
                }
            }
            .padding(16).frame(width: 220, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
            VStack(alignment: .leading, spacing: 16) {
                OverviewView().quickCleanCard
                HStack(spacing: 16) {
                    Card { CardTitle(title: "Aufräumen", page: .cleanup); Text("Beispiel-Karte").foregroundStyle(.secondary) }
                    Card { CardTitle(title: "Sicherheit", page: .security); Text("Beispiel-Karte").foregroundStyle(.secondary) }
                }
                MyToolsGrid()
            }
            .padding(20).frame(width: 760)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .light)
        let r = ImageRenderer(content: view)
        r.scale = 1
        if let img = r.nsImage, let tiff = img.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: path))
        }
    }
}
