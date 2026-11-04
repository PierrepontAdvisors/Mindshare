import AppKit
import MemoryCore
import SwiftUI

private let limitChoicesGB = [1, 2, 3, 4, 6, 8, 12]

/// Takes plain values and compares what it displays, so a row only redraws when something visible changed.
struct AppRow: View, Equatable {
    private enum Cell {
        case logo, memory, percent, limit, status, quit
    }

    let row: AppUsage
    let icon: NSImage
    let totalMemory: UInt64
    let status: LimitStatus
    let limitGB: Int?
    let peakBytes: UInt64
    let onSetLimit: (Int?) -> Void
    let onQuit: (_ force: Bool) -> Void

    @State private var isHovered = false
    @State private var hoveredCell: Cell?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isBackground: Bool { row.appPIDs.isEmpty }

    static func == (a: AppRow, b: AppRow) -> Bool {
        a.row.id == b.row.id
            && a.row.name == b.row.name
            && a.row.appPIDs == b.row.appPIDs
            && a.row.processCount == b.row.processCount
            && memoryText(a.row.bytes) == memoryText(b.row.bytes)
            && percentText(a.row.bytes, ofTotal: a.totalMemory) == percentText(b.row.bytes, ofTotal: b.totalMemory)
            && a.status == b.status
            && a.limitGB == b.limitGB
            && memoryText(a.peakBytes) == memoryText(b.peakBytes)
    }

    var body: some View {
        HStack(spacing: 0) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: Tokens.appIcon, height: Tokens.appIcon)
                .cell(Tokens.Column.icon)
                .hoverDetail(.logo, $hoveredCell)
                .accessibilityHidden(true)
            Color.clear.cell(Tokens.Column.gap)
            // Hovering any cell swaps the name for detail about it: instant, and right where you're looking.
            Text(detail ?? row.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(detail == nil ? 1 : 0.85)
                .foregroundStyle(detail != nil || isBackground ? .secondary : .primary)
                .cell(Tokens.Column.name, .leading)
                .help(row.name)
            Text(memoryText(row.bytes))
                .monospacedDigit()
                .cell(Tokens.Column.memory, .trailing)
                .hoverDetail(.memory, $hoveredCell)
            Text(percentText(row.bytes, ofTotal: totalMemory))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .cell(Tokens.Column.percent, .trailing)
                .hoverDetail(.percent, $hoveredCell)
            limitMenu
            Image(systemName: status.symbol)
                .font(status == .noLimit ? .system(size: status.iconSize) : Tokens.Typography.statusIcon)
                .foregroundStyle(status.color)
                .cell(Tokens.Column.status)
                .hoverDetail(.status, $hoveredCell)
                .accessibilityLabel(status.label)
                .accessibilityValue(limitText)
            quitButton
        }
        .font(Tokens.Typography.data)
        .padding(.horizontal, Tokens.rowInset)
        .background {
            RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                .fill(Color.primary.opacity(isHovered ? 0.07 : 0))
        }
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : Motion.hover, value: isHovered)
        .animation(reduceMotion ? nil : Motion.hover, value: hoveredCell)
    }

    private var limitText: String {
        limitDetail(row, limitsGB: limitGB.map { [row.id: $0] } ?? [:])
    }

    private var detail: String? {
        switch hoveredCell {
        case nil: return nil
        case .logo:
            let processes = row.processCount == 1 ? "1 process" : "\(row.processCount) processes"
            return isBackground ? "Background, \(processes)" : processes
        case .memory: return "Peak \(memoryText(peakBytes)) so far"
        case .percent: return "\(percentText(row.bytes, ofTotal: totalMemory)) of \(totalMemory >> 30) GB RAM"
        case .limit: return limitGB == nil ? "Click to set a limit" : "Click to change limit"
        case .status: return limitText
        case .quit: return "Quit, ⌥-click to force"
        }
    }

    private var limitMenu: some View {
        Menu {
            Button("No limit") { onSetLimit(nil) }
            ForEach(limitChoicesGB, id: \.self) { gb in
                Button("\(gb) GB") { onSetLimit(gb) }
            }
        } label: {
            Text(limitGB.map { "\($0) GB" } ?? "–")
                .monospacedDigit()
                .padding(.trailing, 4)
                .cell(Tokens.Column.limit, .trailing)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .modifier(HoverEmphasis())
        .hoverDetail(.limit, $hoveredCell)
        .accessibilityLabel("Memory limit for \(row.name)")
    }

    @ViewBuilder private var quitButton: some View {
        if isBackground {
            // An empty view would collapse this cell and shift the whole row out of the grid.
            Color.clear.cell(Tokens.Column.quit)
        } else {
            Button { onQuit(NSEvent.modifierFlags.contains(.option)) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .cell(Tokens.Column.quit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // Always visible, because quitting shouldn't depend on hover; it just stays quiet until the row is hovered.
            .modifier(HoverEmphasis(tint: .red, rest: isHovered ? .secondary : .secondary.opacity(0.5)))
            .hoverDetail(.quit, $hoveredCell)
            .accessibilityLabel("Quit \(row.name)")
            .accessibilityAction(named: "Force quit \(row.name)") { onQuit(true) }
        }
    }
}
