import SwiftUI

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.largeTitle.bold())
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }
}

struct UsageBar: View {
    let fraction: Double

    var color: Color { fraction > 0.9 ? .red : fraction > 0.75 ? .orange : .accentColor }

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
