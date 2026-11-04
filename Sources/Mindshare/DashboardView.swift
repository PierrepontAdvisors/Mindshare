import MemoryCore
import SwiftUI

private let totalMemory = ProcessInfo.processInfo.physicalMemory

struct DashboardView: View {
    @ObservedObject var monitor: Monitor
    @AppStorage("sortKey") private var sortKey = SortKey.memory
    @AppStorage("sortAscending") private var ascending = false
    @AppStorage("showAll") private var showAll = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sortedRows: [AppUsage] {
        let shown = showAll ? monitor.rows : quittableRows(monitor.rows, limitsGB: monitor.limitsGB)
        return sortRows(shown, by: sortKey, ascending: ascending, limitsGB: monitor.limitsGB)
    }

    /// Whole rows only, and no taller than the list needs.
    private var listHeight: CGFloat {
        Tokens.rowPitch * min(CGFloat(sortedRows.count), Tokens.visibleRows)
    }

    private var arrowSymbol: String { ascending ? "chevron.up" : "chevron.down" }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(sortedRows) { row in
                        VStack(spacing: 0) {
                            AppRow(
                                row: row,
                                icon: monitor.icons.icon(for: row),
                                totalMemory: totalMemory,
                                status: limitStatus(row, limitsGB: monitor.limitsGB),
                                limitGB: monitor.limitsGB[row.id],
                                peakBytes: monitor.peaks[row.id] ?? row.bytes,
                                onSetLimit: { monitor.setLimit($0, for: row.id) },
                                onQuit: { monitor.quit(row, force: $0) }
                            )
                            .equatable()
                            Divider().opacity(0.4)
                        }
                        .transition(.opacity)
                    }
                }
                .animation(reduceMotion ? nil : Motion.reorder, value: sortedRows.map(\.id))
            }
            .frame(height: listHeight)
            FooterView(monitor: monitor, showAll: $showAll, totalMemory: totalMemory)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(width: Tokens.panelWidth)
    }

    private var header: some View {
        HStack(spacing: 0) {
            Color.clear.cell(Tokens.Column.icon)
            Color.clear.cell(Tokens.Column.gap)
            headerCell(.name, title: "name", width: Tokens.Column.name, alignment: .leading) { Text("App") }
            headerCell(.memory, title: "memory", width: Tokens.Column.memory, alignment: .trailing) { Text("Memory") }
            // Percent sorts the same way as memory, so only the Memory column shows the arrow.
            headerCell(
                .memory,
                title: "share of \(totalMemory >> 30) GB RAM",
                width: Tokens.Column.percent,
                alignment: .trailing,
                showsArrow: false
            ) { Text("%") }
            headerCell(.limit, title: "limit", width: Tokens.Column.limit, alignment: .trailing) {
                Text("Limit").padding(.trailing, 4)
            }
            headerCell(.status, title: "status", width: Tokens.Column.status, alignment: .center, showsArrow: false) {
                Image(systemName: sortKey == .status ? arrowSymbol : "circle.fill")
                    .font(sortKey == .status ? Tokens.Typography.sortArrow : .system(size: 4))
            }
            Color.clear.cell(Tokens.Column.quit)
        }
        .font(Tokens.Typography.label)
        .padding(.horizontal, Tokens.rowInset)
    }

    private func headerCell<Title: View>(
        _ key: SortKey,
        title: String,
        width: CGFloat,
        alignment: Alignment,
        showsArrow: Bool = true,
        @ViewBuilder content: () -> Title
    ) -> some View {
        let isActive = key == sortKey
        let arrow = showsArrow && isActive
        return Button { sort(by: key) } label: {
            // The arrow sits on the free side of the title, so the title stays flush with its column.
            HStack(spacing: 3) {
                if arrow && alignment == .trailing { sortArrow }
                content()
                if arrow && alignment != .trailing { sortArrow }
            }
            .cell(width, alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HoverEmphasis(rest: isActive ? .primary : .secondary))
        .help("Sort by \(title)")
        .accessibilityLabel("Sort by \(title)")
        .accessibilityValue(isActive ? (ascending ? "Sorted ascending" : "Sorted descending") : "")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var sortArrow: some View {
        Image(systemName: arrowSymbol).font(Tokens.Typography.sortArrow)
    }

    private func sort(by key: SortKey) {
        if key == sortKey {
            ascending.toggle()
        } else {
            sortKey = key
            ascending = key == .name
        }
    }
}
