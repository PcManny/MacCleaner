import SwiftUI

/// Colours taken from the app icon.
enum Brand {
    static let blue = Color(red: 0.12, green: 0.44, blue: 0.85)      // #1E6FD9
    static let lightBlue = Color(red: 0.35, green: 0.82, blue: 1.0)  // #5AD1FF
    static let deepBlue = Color(red: 0.07, green: 0.24, blue: 0.61)  // #123E9C
    static let orange = Color(red: 0.94, green: 0.48, blue: 0.12)    // #F07B1E
}

/// White symbol on a coloured rounded square, like the icons in System Settings.
struct IconTile: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
            .fill(color.gradient)
            .frame(width: size, height: size)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.55, weight: .semibold)).foregroundStyle(.white))
    }
}

/// Card heading with a coloured tile.
struct CardTitle: View {
    let title: String
    let page: Page
    var body: some View {
        HStack(spacing: 8) {
            IconTile(symbol: page.icon, color: page.color, size: 24)
            Text(title).font(.headline)
        }
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    private var page: Page? { Page(rawValue: title) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let page { IconTile(symbol: page.icon, color: page.color, size: 46) }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background {
            if let page {
                LinearGradient(colors: [page.color.opacity(0.22), page.color.opacity(0.0)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
        }
    }
}

struct UsageBar: View {
    let fraction: Double

    var color: Color { fraction > 0.9 ? .red : fraction > 0.75 ? .orange : Brand.blue }

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(width: max(g.size.width * min(fraction, 1), 4))
            }
        }
    }
}

struct LevelIcon: View {
    let level: Level
    var body: some View {
        Image(systemName: level.symbol).foregroundStyle(level.color).font(.title3)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct Footer<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) { content }.padding(14)
        }
    }
}

struct LeftoverRow: View {
    @Binding var item: Leftover

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $item.selected).toggleStyle(.checkbox).labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.path(item.url.path)).lineLimit(1).truncationMode(.middle)
                Text(item.note).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
            Button { reveal(item.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless).help("Im Finder zeigen")
        }
    }
}
