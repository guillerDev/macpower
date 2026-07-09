import SwiftUI

/// A rounded translucent panel used to group content.
struct Card<Content: View>: View {
    var title: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    if let systemImage { Image(systemName: systemImage) }
                }
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator.opacity(0.5)))
    }
}

/// A single headline number with a caption and optional accent colour.
struct StatTile: View {
    let title: String
    let value: String
    var caption: String?
    var color: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if let caption {
                Text(caption).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A circular progress ring with a centred label.
struct RingGauge: View {
    var fraction: Double  // 0...1
    var color: Color
    var lineWidth: CGFloat = 12
    var label: String
    var caption: String?

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(fraction, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)
            VStack(spacing: 2) {
                Text(label)
                    .font(.system(.title, design: .rounded).weight(.semibold))
                    .contentTransition(.numericText())
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A labelled horizontal meter (used for per-core bars).
struct MeterRow: View {
    let label: String
    let fraction: Double
    let trailing: String
    var color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 30, alignment: .leading)
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule()
                        .fill(color)
                        .frame(width: max(3, geo.size.width * min(max(fraction, 0), 1)))
                        .animation(.easeOut(duration: 0.35), value: fraction)
                }
            }
            .frame(height: 10)
            Text(trailing)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 62, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}
