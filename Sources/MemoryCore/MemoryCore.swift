import Foundation

public struct OwnerApp: Hashable {
    public let id: String
    public let name: String
    public let pid: Int32

    public init(id: String, name: String, pid: Int32) {
        self.id = id
        self.name = name
        self.pid = pid
    }
}

public struct ProcessSample {
    public let name: String
    public let bytes: UInt64
    public let owner: OwnerApp?
    public let path: String

    public init(name: String, bytes: UInt64, owner: OwnerApp?, path: String = "") {
        self.name = name
        self.bytes = bytes
        self.owner = owner
        self.path = path
    }
}

public struct AppUsage: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let bytes: UInt64
    public let processCount: Int
    public let appPIDs: [Int32]
    public let executablePath: String

    public init(
        id: String,
        name: String,
        bytes: UInt64,
        processCount: Int,
        appPIDs: [Int32],
        executablePath: String = ""
    ) {
        self.id = id
        self.name = name
        self.bytes = bytes
        self.processCount = processCount
        self.appPIDs = appPIDs
        self.executablePath = executablePath
    }
}

public enum MemoryState {
    case normal, warning, critical, unknown
}

/// What the menu bar shows. The fill is stepped so small changes don't cause a redraw.
public struct MenuBarStatus: Equatable {
    public let state: MemoryState
    public let level: Int

    public init(state: MemoryState, level: Int) {
        self.state = state
        self.level = level
    }
}

public let menuBarLevels = 20
public let refreshChoices = [1, 2, 5, 10, 30, 60]
public let defaultRefreshSeconds = 5

public enum SortKey: String {
    case status, name, memory, limit
}

public enum LimitStatus: Int {
    case noLimit, underLimit, nearLimit, overLimit
}

private let bytesPerGB: UInt64 = 1 << 30
private let minimumBackgroundBytes: UInt64 = 100 << 20
private let minimumAppBytes: UInt64 = 20 << 20

private func limitBytes(_ gb: Int) -> UInt64 { UInt64(gb) * bytesPerGB }

public func groupByApp(_ samples: [ProcessSample]) -> [AppUsage] {
    let groups = Dictionary(grouping: samples) { $0.owner?.id ?? "process:\($0.name)" }
    let rows = groups.map { id, group -> AppUsage in
        let owners = group.compactMap(\.owner)
        return AppUsage(
            id: id,
            name: owners.first?.name ?? group[0].name,
            bytes: group.reduce(UInt64(0)) { $0 + $1.bytes },
            processCount: group.count,
            appPIDs: Set(owners.map(\.pid)).sorted(),
            executablePath: group[0].path
        )
    }
    return rows.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.name < $1.name }
}

public func visibleRows(_ usage: [AppUsage], limitsGB: [String: Int]) -> [AppUsage] {
    usage.filter { !$0.appPIDs.isEmpty || $0.bytes >= minimumBackgroundBytes || limitsGB[$0.id] != nil }
}

public func limitStatus(_ row: AppUsage, limitsGB: [String: Int]) -> LimitStatus {
    guard let gb = limitsGB[row.id] else { return .noLimit }
    let limit = limitBytes(gb)
    if row.bytes > limit { return .overLimit }
    return row.bytes >= limit * 9 / 10 ? .nearLimit : .underLimit
}

public func isOverLimit(_ row: AppUsage, limitsGB: [String: Int]) -> Bool {
    limitStatus(row, limitsGB: limitsGB) == .overLimit
}

/// Warns once per crossing. A warning only resets below 90% of the limit, so an app hovering at its limit stays quiet.
public func checkLimits(
    usage: [AppUsage],
    limitsGB: [String: Int],
    warned: Set<String>
) -> (warned: Set<String>, newlyOver: [AppUsage]) {
    let newlyOver = usage.filter { isOverLimit($0, limitsGB: limitsGB) && !warned.contains($0.id) }
    let stillWarned = usage.filter {
        warned.contains($0.id) && [.nearLimit, .overLimit].contains(limitStatus($0, limitsGB: limitsGB))
    }
    return (Set((stillWarned + newlyOver).map(\.id)), newlyOver)
}

public func sortRows(
    _ rows: [AppUsage],
    by key: SortKey,
    ascending: Bool,
    limitsGB: [String: Int]
) -> [AppUsage] {
    func comesBefore(_ a: AppUsage, _ b: AppUsage) -> Bool {
        switch key {
        case .name: return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        case .memory: return a.bytes < b.bytes
        case .limit: return (limitsGB[a.id] ?? 0) < (limitsGB[b.id] ?? 0)
        case .status:
            return limitStatus(a, limitsGB: limitsGB).rawValue < limitStatus(b, limitsGB: limitsGB).rawValue
        }
    }
    return rows.sorted { a, b in
        if comesBefore(a, b) { return ascending }
        if comesBefore(b, a) { return !ascending }
        // Ties keep a fixed order so rows don't shuffle on every refresh.
        return a.bytes != b.bytes ? a.bytes > b.bytes : a.name < b.name
    }
}

public func percentText(_ bytes: UInt64, ofTotal total: UInt64) -> String {
    guard total > 0 else { return "–" }
    let percent = Double(bytes) / Double(total) * 100
    return percent < 1 ? "<1%" : "\(Int(percent.rounded()))%"
}

/// Switches to gigabytes at 1000 MB so a value never needs four digits.
public func memoryText(_ bytes: UInt64) -> String {
    let megabytes = Double(bytes) / Double(1 << 20)
    if megabytes < 999.5 { return String(format: "%.0f MB", megabytes) }
    return String(format: "%.1f GB", megabytes / 1024)
}

public func enclosingAppBundle(_ path: String) -> String? {
    path.range(of: ".app/").map { String(path[..<$0.lowerBound]) + ".app" }
}

/// The default view: apps worth quitting. Keeps anything with a limit, so a warning always has a row to point at.
public func quittableRows(_ rows: [AppUsage], limitsGB: [String: Int]) -> [AppUsage] {
    rows.filter { (!$0.appPIDs.isEmpty && $0.bytes >= minimumAppBytes) || limitsGB[$0.id] != nil }
}

/// Levels are the kernel's own memory pressure values, the same signal Activity Monitor graphs.
public func memoryState(pressureLevel: Int32) -> MemoryState {
    switch pressureLevel {
    case 1: return .normal
    case 2: return .warning
    case 4: return .critical
    default: return .unknown
    }
}

public func usedMemoryText(_ used: UInt64, ofTotal total: UInt64) -> String {
    String(format: "%.1f of %d GB", Double(used) / Double(bytesPerGB), Int(total / bytesPerGB))
}

public func validRefreshSeconds(_ stored: Int) -> Int {
    refreshChoices.contains(stored) ? stored : defaultRefreshSeconds
}

public func limitDetail(_ row: AppUsage, limitsGB: [String: Int]) -> String {
    guard let gb = limitsGB[row.id] else { return "No limit set" }
    let limit = limitBytes(gb)
    return row.bytes > limit
        ? "\(memoryText(row.bytes - limit)) over limit"
        : "\(memoryText(limit - row.bytes)) under limit"
}

public func menuBarStatus(usedBytes: UInt64, totalBytes: UInt64, state: MemoryState, anyOverLimit: Bool) -> MenuBarStatus {
    let share = totalBytes > 0 ? min(Double(usedBytes) / Double(totalBytes), 1) : 0
    let isCalm = state == .normal || state == .unknown
    return MenuBarStatus(
        state: anyOverLimit && isCalm ? .warning : state,
        level: Int((share * Double(menuBarLevels)).rounded())
    )
}

/// Apps that are launching or already gone report a pid of -1, so several can share it. They have no processes to count.
public func ownersByPID(_ owners: [OwnerApp]) -> [Int32: OwnerApp] {
    Dictionary(owners.filter { $0.pid > 0 }.map { ($0.pid, $0) }) { first, _ in first }
}

/// The highest total seen per app while it stays open. Tracked here because adding up each process's own
/// peak would overstate apps whose many processes peak at different times.
public func updatedPeaks(_ peaks: [String: UInt64], rows: [AppUsage]) -> [String: UInt64] {
    Dictionary(rows.map { ($0.id, max($0.bytes, peaks[$0.id] ?? 0)) }) { first, _ in first }
}

public func memoryBreakdownText(
    appBytes: UInt64,
    wiredBytes: UInt64,
    compressedBytes: UInt64,
    totalBytes: UInt64,
    stateLabel: String
) -> String {
    func gigabytes(_ bytes: UInt64) -> String { String(format: "%.1f", Double(bytes) / Double(bytesPerGB)) }
    let used = appBytes + wiredBytes + compressedBytes
    let free = totalBytes > used ? totalBytes - used : 0
    return "\(stateLabel) · Apps \(gigabytes(appBytes)) · System \(gigabytes(wiredBytes))"
        + " · Compressed \(gigabytes(compressedBytes)) · Free \(gigabytes(free)) GB"
}
