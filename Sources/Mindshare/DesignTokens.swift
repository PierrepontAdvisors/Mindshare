import MemoryCore
import SwiftUI

/// Every size, type style and timing the panel uses, on a 2pt spacing scale.
enum Tokens {
    static let panelWidth: CGFloat = 378
    static let rowHeight: CGFloat = 26
    static let rowPitch: CGFloat = 27 // A row plus its 1pt divider.
    static let rowInset: CGFloat = 6
    static let visibleRows: CGFloat = 14
    static let cornerRadius: CGFloat = 5
    static let appIcon: CGFloat = 16
    static let pie: CGFloat = 14

    enum Column {
        static let icon: CGFloat = 20
        static let gap: CGFloat = 6
        static let name: CGFloat = 130
        static let memory: CGFloat = 60
        static let percent: CGFloat = 40
        static let limit: CGFloat = 46
        static let status: CGFloat = 22
        static let quit: CGFloat = 26
    }

    enum Typography {
        static let data = Font.system(size: 12)
        static let label = Font.system(size: 11, weight: .medium)
        static let footer = Font.system(size: 11)
        static let statusIcon = Font.system(size: 12)
        static let sortArrow = Font.system(size: 7, weight: .bold)
    }
}

/// Motion stays on hover and row order. Per-row digit and symbol effects kept SwiftUI render data alive
/// on every refresh, which cost about 10% CPU and 1 MB of memory a second.
enum Motion {
    static let hover = Animation.easeOut(duration: 0.15)
    static let value = Animation.easeOut(duration: 0.25)
    static let reorder = Animation.spring(duration: 0.3, bounce: 0)
}

extension View {
    /// One grid cell: fixed size, with its content placed by column type.
    func cell(_ width: CGFloat, _ alignment: Alignment = .center) -> some View {
        frame(width: width, height: Tokens.rowHeight, alignment: alignment)
    }
}

/// The one hover state every control shares: colour shifts and a soft fill fades in, without moving anything.
struct HoverEmphasis: ViewModifier {
    var tint: Color = .primary
    var rest: Color = .secondary

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .foregroundStyle(isHovered ? tint : rest)
            .background {
                RoundedRectangle(cornerRadius: Tokens.cornerRadius)
                    .fill(tint.opacity(isHovered ? 0.12 : 0))
                    .padding(.vertical, 3)
            }
            .onHover { isHovered = $0 }
            .animation(reduceMotion ? nil : Motion.hover, value: isHovered)
    }
}

extension View {
    /// Reports which item the pointer is on, so the row or footer can show detail about it.
    func hoverDetail<Item: Equatable>(_ item: Item, _ hovered: Binding<Item?>) -> some View {
        onHover { isInside in
            if isInside {
                hovered.wrappedValue = item
            } else if hovered.wrappedValue == item {
                hovered.wrappedValue = nil
            }
        }
    }
}

extension LimitStatus {
    var symbol: String {
        switch self {
        case .noLimit: return "circle.fill"
        case .underLimit: return "checkmark.circle.fill"
        case .nearLimit: return "exclamationmark.triangle.fill"
        case .overLimit: return "xmark.octagon.fill"
        }
    }

    /// The no-limit dot stays small so rows with a real status stand out.
    var iconSize: CGFloat { self == .noLimit ? 4 : 12 }

    var color: Color {
        switch self {
        case .noLimit: return .secondary
        case .underLimit: return .green
        case .nearLimit: return .orange
        case .overLimit: return .red
        }
    }

    var label: String {
        switch self {
        case .noLimit: return "No limit set"
        case .underLimit: return "Under limit"
        case .nearLimit: return "Near limit"
        case .overLimit: return "Over limit"
        }
    }
}

extension MemoryState {
    var symbol: String {
        switch self {
        case .normal: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .normal: return .green
        case .warning: return .orange
        case .critical: return .red
        case .unknown: return .secondary
        }
    }

    var label: String {
        switch self {
        case .normal: return "Memory pressure: normal"
        case .warning: return "Memory pressure: elevated"
        case .critical: return "Memory pressure: critical"
        case .unknown: return "Memory pressure: unavailable"
        }
    }

    var shortLabel: String {
        switch self {
        case .normal: return "Normal"
        case .warning: return "Elevated"
        case .critical: return "Critical"
        case .unknown: return "Unknown"
        }
    }
}
