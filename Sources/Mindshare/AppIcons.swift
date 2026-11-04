import AppKit
import MemoryCore

/// Looks each icon up once, and only when the panel shows that row, so a closed panel loads none.
final class AppIcons {
    private var cache: [String: NSImage] = [:]

    func icon(for row: AppUsage) -> NSImage {
        if let cached = cache[row.id] { return cached }
        let icon = lookUp(row)
        cache[row.id] = icon
        return icon
    }

    private func lookUp(_ row: AppUsage) -> NSImage {
        if let pid = row.appPIDs.first, let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            return icon
        }
        if let bundle = enclosingAppBundle(row.executablePath) {
            return NSWorkspace.shared.icon(forFile: bundle)
        }
        return NSWorkspace.shared.icon(for: row.appPIDs.isEmpty ? .unixExecutable : .application)
    }
}
