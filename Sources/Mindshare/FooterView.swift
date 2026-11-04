import AppKit
import MemoryCore
import SwiftUI

struct FooterView: View {
    private enum Item {
        case pie, showAll, refresh, notifications, quit
    }

    @ObservedObject var monitor: Monitor
    @Binding var showAll: Bool
    let totalMemory: UInt64

    @State private var hoveredItem: Item?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            if let system = monitor.system {
                pie(system).hoverDetail(.pie, $hoveredItem)
            }
            ZStack(alignment: .leading) {
                summary.opacity(hoveredItem == .pie ? 0 : 1)
                // The breakdown needs the full width, so it takes over the line while the pointer is on the pie.
                if hoveredItem == .pie, let system = monitor.system {
                    Text(breakdown(system)).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(.secondary)
                }
            }
        }
        .font(Tokens.Typography.footer)
        .padding(.horizontal, Tokens.rowInset)
        .animation(reduceMotion ? nil : Motion.hover, value: hoveredItem)
    }

    private var summary: some View {
        HStack(spacing: 8) {
            if let system = monitor.system { usage(system) }
            Spacer(minLength: 0)
            Toggle("Show all", isOn: $showAll)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .foregroundStyle(.secondary)
                .fixedSize()
                .hoverDetail(.showAll, $hoveredItem)
            refreshMenu
            if monitor.notificationsOff { notificationsButton }
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").cell(Tokens.Column.quit).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .modifier(HoverEmphasis())
            .hoverDetail(.quit, $hoveredItem)
            .accessibilityLabel("Quit Mindshare")
        }
    }

    private func breakdown(_ system: SystemMemory) -> String {
        memoryBreakdownText(
            appBytes: system.appBytes,
            wiredBytes: system.wiredBytes,
            compressedBytes: system.compressedBytes,
            totalBytes: totalMemory,
            stateLabel: system.state.shortLabel
        )
    }

    private var hint: String? {
        switch hoveredItem {
        case nil, .pie: return nil
        case .showAll: return showAll ? "All apps, big background" : "Showing main apps"
        case .refresh: return "Checks every \(monitor.refreshSeconds)s"
        case .notifications: return "Turn on notifications"
        case .quit: return "Quit Mindshare"
        }
    }

    private func usage(_ system: SystemMemory) -> some View {
        HStack(spacing: 6) {
            // Green needs no extra mark, but amber and red shouldn't rely on colour alone.
            if system.state != .normal && hint == nil {
                Image(systemName: system.state.symbol)
                    .foregroundStyle(system.state.color)
                    .accessibilityHidden(true)
            }
            if let hint {
                Text(hint).lineLimit(1).minimumScaleFactor(0.85).foregroundStyle(.secondary)
            } else {
                let used = Text(usedMemoryText(system.usedBytes, ofTotal: totalMemory)).monospacedDigit()
                // The percent gives way first, so the main number is never cut off.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        used
                        Text(percentText(system.usedBytes, ofTotal: totalMemory))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    used
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(system.state.label)
        .accessibilityValue(breakdown(system))
    }

    /// A trimmed circle stroked as wide as its radius draws as a pie slice.
    private func pie(_ system: SystemMemory) -> some View {
        let share = min(Double(system.usedBytes) / Double(max(totalMemory, 1)), 1)
        return ZStack {
            Circle().fill(Color.primary.opacity(0.12))
            Circle()
                .trim(from: 0, to: share)
                .stroke(system.state.color, style: StrokeStyle(lineWidth: Tokens.pie / 2))
                .padding(Tokens.pie / 4)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Tokens.pie, height: Tokens.pie)
        .animation(reduceMotion ? nil : Motion.value, value: share)
    }

    private var refreshMenu: some View {
        Menu {
            ForEach(refreshChoices, id: \.self) { seconds in
                Button("Every \(seconds)s") { monitor.setRefreshSeconds(seconds) }
            }
            Divider()
            Toggle("Open at login", isOn: Binding(get: { monitor.opensAtLogin }, set: monitor.setOpensAtLogin))
        } label: {
            Label("\(monitor.refreshSeconds)s", systemImage: "arrow.clockwise")
                .padding(.horizontal, 4)
                .frame(height: Tokens.rowHeight)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .modifier(HoverEmphasis())
        .hoverDetail(.refresh, $hoveredItem)
        .accessibilityLabel("Refresh interval")
    }

    private var notificationsButton: some View {
        Button { monitor.openNotificationSettings() } label: {
            Image(systemName: "bell.slash")
                .cell(Tokens.Column.quit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(HoverEmphasis(tint: .orange, rest: .orange))
        .hoverDetail(.notifications, $hoveredItem)
        .accessibilityLabel("Turn on notifications")
    }
}
