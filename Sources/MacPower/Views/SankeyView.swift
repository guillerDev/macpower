import SwiftUI

struct SankeyNode: Identifiable {
    let id: String
    let label: String
    let column: Int
    let value: Double
    let color: Color
}

struct SankeyLink: Identifiable {
    var id: String { "\(source)->\(target)" }
    let source: String
    let target: String
    let value: Double
}

/// A generic left-to-right Sankey diagram. Node heights and ribbon widths are
/// proportional to their value using one shared watts-to-pixels scale, so flows
/// line up across columns.
struct SankeyView: View {
    let nodes: [SankeyNode]
    let links: [SankeyLink]
    /// When non-nil, node ids in the set render fully and everything else is
    /// dimmed. `nil` means show everything at full strength.
    var highlighted: Set<String>? = nil

    private let barWidth: CGFloat = 13
    private let nodeGap: CGFloat = 14
    private let labelSpace: CGFloat = 4
    private let minBar: CGFloat = 3  // shortest a node bar can be
    private let minLink: CGFloat = 2  // thinnest a ribbon can be (keeps tiny flows visible)

    var body: some View {
        Canvas { context, size in
            guard let maxColumn = nodes.map(\.column).max() else { return }

            // Measure real label widths so padding always fits, then lay out.
            let big = CGSize(width: 500, height: 100)
            func labelWidth(_ node: SankeyNode) -> CGFloat {
                context.resolve(labelText(for: node)).measure(in: big).width
            }
            let leftPad =
                (nodes.filter { $0.column == 0 }.map(labelWidth).max() ?? 0)
                + barWidth / 2 + labelSpace + 6
            let rightPad =
                (nodes.filter { $0.column == maxColumn }.map(labelWidth).max() ?? 0)
                + barWidth / 2 + labelSpace + 6

            let layout = computeLayout(in: size, leftPad: leftPad, rightPad: rightPad)
            guard !layout.frames.isEmpty else { return }

            // Ribbons first, so node bars sit on top of them.
            drawLinks(context: context, layout: layout)

            for node in nodes {
                guard let frame = layout.frames[node.id] else { continue }
                let active = isActive(node.id)
                let bar = Path(roundedRect: frame, cornerRadius: 3)
                context.fill(bar, with: .color(node.color.opacity(active ? 1 : 0.15)))

                // Label + value beside the bar (right of last column, left otherwise).
                let isLast = node.column == layout.maxColumn
                let anchorPoint = CGPoint(
                    x: isLast ? frame.maxX + labelSpace + 2 : frame.minX - labelSpace - 2,
                    y: frame.midY)
                var labelContext = context
                labelContext.opacity = active ? 1 : 0.3
                labelContext.draw(
                    context.resolve(labelText(for: node)),
                    at: anchorPoint,
                    anchor: isLast ? .leading : .trailing)
            }
        }
    }

    private func labelText(for node: SankeyNode) -> Text {
        Text(node.label).font(.system(size: 11, weight: .semibold))
            + Text("  " + Fmt.power(node.value)).font(.system(size: 10)).foregroundColor(.secondary)
    }

    // MARK: - Layout

    private struct Layout {
        var frames: [String: CGRect] = [:]
        var scale: CGFloat = 0
        var maxColumn: Int = 0
        var columnX: [Int: CGFloat] = [:]
    }

    private func computeLayout(in size: CGSize, leftPad: CGFloat, rightPad: CGFloat) -> Layout {
        var layout = Layout()
        let columns = Dictionary(grouping: nodes, by: \.column)
        guard let maxColumn = columns.keys.max() else { return layout }
        layout.maxColumn = maxColumn

        // Shared scale: the fullest column defines watts-per-pixel.
        var maxTotal = 0.0
        for (_, colNodes) in columns {
            maxTotal = max(maxTotal, colNodes.reduce(0) { $0 + $1.value })
        }
        guard maxTotal > 0 else { return layout }

        // Column x positions run between the measured label paddings.
        let usableWidth = max(size.width - leftPad - rightPad, 1)
        let columnCount = maxColumn + 1
        let columnSpacing = columnCount > 1 ? usableWidth / CGFloat(columnCount - 1) : 0
        for c in 0...maxColumn {
            layout.columnX[c] = leftPad + columnSpacing * CGFloat(c)
        }

        // The fullest column also spends fixed pixels on inter-node gaps; subtract
        // those (plus a small vertical margin) before deriving the watts-to-pixels
        // scale, otherwise a multi-node column overflows the canvas.
        let maxNodes = columns.values.map(\.count).max() ?? 1
        let gapTotal = CGFloat(max(0, maxNodes - 1)) * nodeGap
        let vMargin: CGFloat = 8
        let availableHeight = max(size.height - gapTotal - vMargin * 2, 1)
        let scale = availableHeight / maxTotal
        layout.scale = scale

        // Sum the ribbon widths on each side of every node using the SAME width
        // formula as drawing, so a node is never shorter than the ribbons it
        // carries (otherwise floored tiny ribbons overflow the bar — e.g. DRAM
        // spilling past the bottom of SoC).
        var outWidth: [String: CGFloat] = [:]
        var inWidth: [String: CGFloat] = [:]
        for link in links {
            let w = max(minLink, CGFloat(link.value) * scale)
            outWidth[link.source, default: 0] += w
            inWidth[link.target, default: 0] += w
        }
        func nodeHeight(_ node: SankeyNode) -> CGFloat {
            max(minBar, CGFloat(node.value) * scale, outWidth[node.id] ?? 0, inWidth[node.id] ?? 0)
        }

        for c in 0...maxColumn {
            let colNodes = (columns[c] ?? []).sorted { $0.value > $1.value }
            let totalHeight =
                colNodes.reduce(0) { $0 + nodeHeight($1) }
                + CGFloat(max(0, colNodes.count - 1)) * nodeGap
            var y = (size.height - totalHeight) / 2
            let x = layout.columnX[c] ?? 0
            for node in colNodes {
                let h = nodeHeight(node)
                layout.frames[node.id] = CGRect(x: x - barWidth / 2, y: y, width: barWidth, height: h)
                y += h + nodeGap
            }
        }
        return layout
    }

    private func drawLinks(context: GraphicsContext, layout: Layout) {
        // Track how much of each node's edge is already consumed by ribbons.
        var outOffset: [String: CGFloat] = [:]
        var inOffset: [String: CGFloat] = [:]

        for link in links {
            guard let source = layout.frames[link.source],
                let target = layout.frames[link.target],
                let color = nodes.first(where: { $0.id == link.target })?.color
            else { continue }
            let width = max(minLink, CGFloat(link.value) * layout.scale)

            let sy = source.minY + (outOffset[link.source] ?? 0)
            let ty = target.minY + (inOffset[link.target] ?? 0)
            outOffset[link.source, default: 0] += width
            inOffset[link.target, default: 0] += width

            let sx = source.maxX
            let tx = target.minX
            let midX = (sx + tx) / 2

            var path = Path()
            path.move(to: CGPoint(x: sx, y: sy))
            path.addCurve(
                to: CGPoint(x: tx, y: ty),
                control1: CGPoint(x: midX, y: sy),
                control2: CGPoint(x: midX, y: ty))
            path.addLine(to: CGPoint(x: tx, y: ty + width))
            path.addCurve(
                to: CGPoint(x: sx, y: sy + width),
                control1: CGPoint(x: midX, y: ty + width),
                control2: CGPoint(x: midX, y: sy + width))
            path.closeSubpath()

            let active = isActive(link.source) && isActive(link.target)
            context.fill(path, with: .color(color.opacity(active ? 0.35 : 0.05)))
        }
    }

    private func isActive(_ id: String) -> Bool {
        guard let highlighted else { return true }
        return highlighted.contains(id)
    }
}
