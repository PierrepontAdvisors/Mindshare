import Foundation
import MemoryCore

// XCTest and Swift Testing need full Xcode, so these checks run as a plain program: `swift run CoreCheck`.
var failures = 0

func check(_ label: String, _ passed: Bool) {
    print((passed ? "ok    " : "FAIL  ") + label)
    if !passed { failures += 1 }
}

let mb: UInt64 = 1 << 20
let gb: UInt64 = 1 << 30
let chrome = OwnerApp(id: "com.google.Chrome", name: "Google Chrome", pid: 10)

func row(_ id: String, _ bytes: UInt64, pids: [Int32] = [1]) -> AppUsage {
    AppUsage(id: id, name: id, bytes: bytes, processCount: 1, appPIDs: pids)
}

// Grouping
let grouped = groupByApp([
    ProcessSample(name: "Google Chrome", bytes: 100 * mb, owner: chrome),
    ProcessSample(name: "Google Chrome Helper", bytes: 200 * mb, owner: chrome),
    ProcessSample(name: "node", bytes: 500 * mb, owner: nil),
    ProcessSample(name: "node", bytes: 25 * mb, owner: nil),
    ProcessSample(name: "cloudd", bytes: 10 * mb, owner: nil),
])
check("three rows from five processes", grouped.count == 3)
check("largest row first", grouped.first?.name == "node")
check("same-named background processes add up", grouped.first?.bytes == 525 * mb)
check("background rows cannot be quit", grouped.first?.appPIDs == [])
let chromeRow = grouped.first { $0.name == "Google Chrome" }
check("helpers add up under their app", chromeRow?.bytes == 300 * mb)
check("process count covers helpers", chromeRow?.processCount == 2)
check("app row keeps the app's pid once", chromeRow?.appPIDs == [10])

let twoCopies = groupByApp([
    ProcessSample(name: "a", bytes: mb, owner: OwnerApp(id: "x", name: "X", pid: 1)),
    ProcessSample(name: "b", bytes: mb, owner: OwnerApp(id: "x", name: "X", pid: 2)),
])
check("two copies of one app share a row", twoCopies.count == 1 && twoCopies[0].appPIDs == [1, 2])

// Which rows show
let smallApp = row("smallApp", 5 * mb)
let smallTool = row("smallTool", 99 * mb, pids: [])
let bigTool = row("bigTool", 100 * mb, pids: [])
let limitedTool = row("limitedTool", 5 * mb, pids: [])
let shown = visibleRows([smallApp, smallTool, bigTool, limitedTool], limitsGB: [limitedTool.id: 1])
check("every app shows, however small", shown.contains(smallApp))
check("background under 100 MB is hidden", !shown.contains(smallTool))
check("background at 100 MB shows", shown.contains(bigTool))
check("background with a limit always shows", shown.contains(limitedTool))

// Warnings
let limits = ["app": 4]
func at(_ bytes: UInt64) -> [AppUsage] { [row("app", bytes)] }

let crossing = checkLimits(usage: at(5 * gb), limitsGB: limits, warned: [])
check("crossing the limit warns", crossing.newlyOver.map(\.id) == ["app"])
let stillOver = checkLimits(usage: at(6 * gb), limitsGB: limits, warned: crossing.warned)
check("staying over does not warn again", stillOver.newlyOver.isEmpty)
let nearLimit = checkLimits(usage: at(gb * 37 / 10), limitsGB: limits, warned: stillOver.warned)
check("dipping to 3.7 GB of 4 stays quiet", nearLimit.warned.contains("app"))
let recrossNear = checkLimits(usage: at(5 * gb), limitsGB: limits, warned: nearLimit.warned)
check("wobbling around the limit does not re-warn", recrossNear.newlyOver.isEmpty)
let settled = checkLimits(usage: at(3 * gb), limitsGB: limits, warned: recrossNear.warned)
check("falling to 3 GB of 4 resets the warning", settled.warned.isEmpty)
let crossedAgain = checkLimits(usage: at(5 * gb), limitsGB: limits, warned: settled.warned)
check("a fresh crossing warns again", crossedAgain.newlyOver.count == 1)
check("exactly at the limit is not over", checkLimits(usage: at(4 * gb), limitsGB: limits, warned: []).newlyOver.isEmpty)
check("no limit never warns", checkLimits(usage: at(50 * gb), limitsGB: [:], warned: []).newlyOver.isEmpty)
check("a quit app resets its warning", checkLimits(usage: [], limitsGB: limits, warned: ["app"]).warned.isEmpty)
check("removing a limit resets its warning", checkLimits(usage: at(5 * gb), limitsGB: [:], warned: ["app"]).warned.isEmpty)
check("over-limit row is flagged", isOverLimit(row("app", 5 * gb), limitsGB: limits))
check("under-limit row is not flagged", !isOverLimit(row("app", 3 * gb), limitsGB: limits))

// Status
check("no limit has no status", limitStatus(row("app", 50 * gb), limitsGB: [:]) == .noLimit)
check("3 GB of 4 is under", limitStatus(row("app", 3 * gb), limitsGB: limits) == .underLimit)
check("3.6 GB of 4 is near", limitStatus(row("app", gb * 36 / 10), limitsGB: limits) == .nearLimit)
check("exactly 4 GB of 4 is near, not over", limitStatus(row("app", 4 * gb), limitsGB: limits) == .nearLimit)
check("5 GB of 4 is over", limitStatus(row("app", 5 * gb), limitsGB: limits) == .overLimit)

// Sorting
let alpha = row("alpha", 3 * gb)
let beta = row("Beta", 1 * gb)
let gamma = row("gamma", 2 * gb)
let tied = row("aardvark", 2 * gb)
let sortLimits = ["alpha": 2, "gamma": 8]

func order(_ key: SortKey, ascending: Bool) -> [String] {
    sortRows([alpha, beta, gamma, tied], by: key, ascending: ascending, limitsGB: sortLimits).map(\.name)
}

check("memory, largest first", order(.memory, ascending: false) == ["alpha", "aardvark", "gamma", "Beta"])
check("memory, smallest first", order(.memory, ascending: true) == ["Beta", "aardvark", "gamma", "alpha"])
check("names ignore case", order(.name, ascending: true) == ["aardvark", "alpha", "Beta", "gamma"])
check("names reversed", order(.name, ascending: false) == ["gamma", "Beta", "alpha", "aardvark"])
check("worst status first", order(.status, ascending: false) == ["alpha", "gamma", "aardvark", "Beta"])
check("largest limit first, unlimited last", order(.limit, ascending: false) == ["gamma", "alpha", "aardvark", "Beta"])

// Percent of RAM
check("7 GB of 16 rounds to 44%", percentText(7 * gb, ofTotal: 16 * gb) == "44%")
check("16 GB of 16 is 100%", percentText(16 * gb, ofTotal: 16 * gb) == "100%")
check("tiny usage reads <1%", percentText(20 * mb, ofTotal: 16 * gb) == "<1%")
check("zero total does not crash", percentText(gb, ofTotal: 0) == "–")

// Memory text keeps one precision per unit so digits line up in a right-aligned column
check("whole gigabytes keep a decimal", memoryText(3 * gb) == "3.0 GB")
check("gigabytes round to one decimal", memoryText(gb * 714 / 100) == "7.1 GB")
check("megabytes have no decimal", memoryText(mb * 9647 / 10) == "965 MB")
check("small values stay in megabytes", memoryText(12 * mb) == "12 MB")
check("under 1 MB still reads as a number", memoryText(0) == "0 MB")
check("1000 MB switches to gigabytes", memoryText(1000 * mb) == "1.0 GB")
check("999 MB stays in megabytes", memoryText(999 * mb) == "999 MB")

// Finding an icon for a background process
check("finds the app around a binary", enclosingAppBundle("/Applications/Foo.app/Contents/MacOS/Foo") == "/Applications/Foo.app")
check("nested helpers use the outer app", enclosingAppBundle("/Applications/Foo.app/Contents/Helpers/Bar.app/Contents/MacOS/Bar") == "/Applications/Foo.app")
check("a plain tool has no app", enclosingAppBundle("/usr/local/bin/node") == nil)
check("a folder merely containing .app is not an app", enclosingAppBundle("/opt/my.application/bin/tool") == nil)
let pathRow = groupByApp([ProcessSample(name: "node", bytes: mb, owner: nil, path: "/usr/local/bin/node")])
check("background rows keep their binary path", pathRow.first?.executablePath == "/usr/local/bin/node")

// Quittable filter
let closable = row("closable", gb)
let stuck = row("stuck", gb, pids: [])
let watched = row("watched", gb, pids: [])
let filtered = quittableRows([closable, stuck, watched], limitsGB: ["watched": 1])
check("filter keeps apps you can quit", filtered.contains(closable))
check("filter drops what you cannot quit", !filtered.contains(stuck))
check("filter keeps anything you set a limit on, so its warning has a row", filtered.contains(watched))

// Whole-machine memory state
check("level 1 is normal", memoryState(pressureLevel: 1) == .normal)
check("level 2 is warning", memoryState(pressureLevel: 2) == .warning)
check("level 4 is critical", memoryState(pressureLevel: 4) == .critical)
check("anything else is unknown, not falsely green", memoryState(pressureLevel: 0) == .unknown)
check("usage reads as used of total", usedMemoryText(gb * 114 / 10, ofTotal: 16 * gb) == "11.4 of 16 GB")

// Refresh interval
check("a saved choice is kept", validRefreshSeconds(30) == 30)
check("nothing saved uses the default", validRefreshSeconds(0) == defaultRefreshSeconds)
check("a value outside the choices uses the default", validRefreshSeconds(7) == defaultRefreshSeconds)

// Hover detail for the status icon
check("no limit says so", limitDetail(row("app", 5 * gb), limitsGB: [:]) == "No limit set")
check("under limit shows the room left", limitDetail(row("app", 3 * gb), limitsGB: limits) == "1.0 GB under limit")
check("small gaps read in megabytes", limitDetail(row("app", 4 * gb - 205 * mb), limitsGB: limits) == "205 MB under limit")
check("over limit shows the excess", limitDetail(row("app", gb * 56 / 10), limitsGB: limits) == "1.6 GB over limit")

// Menu bar status
let calm = menuBarStatus(usedBytes: gb * 126 / 10, totalBytes: 16 * gb, state: .normal, anyOverLimit: false)
check("12.6 of 16 GB fills 16 of 20 steps", calm.level == 16)
check("all well stays normal", calm.state == .normal)
check("an app over its limit turns a calm Mac amber", menuBarStatus(usedBytes: gb, totalBytes: 16 * gb, state: .normal, anyOverLimit: true).state == .warning)
check("an app over its limit also shows when pressure is unknown", menuBarStatus(usedBytes: gb, totalBytes: 16 * gb, state: .unknown, anyOverLimit: true).state == .warning)
check("critical pressure stays red", menuBarStatus(usedBytes: gb, totalBytes: 16 * gb, state: .critical, anyOverLimit: true).state == .critical)
check("elevated pressure stays amber", menuBarStatus(usedBytes: gb, totalBytes: 16 * gb, state: .warning, anyOverLimit: false).state == .warning)
check("unknown stays unknown, not falsely green", menuBarStatus(usedBytes: gb, totalBytes: 16 * gb, state: .unknown, anyOverLimit: false).state == .unknown)
check("usage above total stays full", menuBarStatus(usedBytes: 20 * gb, totalBytes: 16 * gb, state: .normal, anyOverLimit: false).level == menuBarLevels)
check("zero total reads empty", menuBarStatus(usedBytes: gb, totalBytes: 0, state: .normal, anyOverLimit: false).level == 0)
check("a tiny change does not redraw", calm == menuBarStatus(usedBytes: gb * 1262 / 100, totalBytes: 16 * gb, state: .normal, anyOverLimit: false))

// Apps that are launching or already gone can report a pid of -1
let ghostOne = OwnerApp(id: "a", name: "A", pid: -1)
let ghostTwo = OwnerApp(id: "b", name: "B", pid: -1)
let realApp = OwnerApp(id: "c", name: "C", pid: 42)
let owners = ownersByPID([ghostOne, ghostTwo, realApp])
check("apps without a process are ignored, without crashing", owners == [42: realApp])
check("a repeated pid keeps the first app", ownersByPID([realApp, OwnerApp(id: "d", name: "D", pid: 42)])[42] == realApp)

// Default view hides tiny helper apps
let tinyApp = row("tiny", 19 * mb)
let smallEnough = row("small", 20 * mb)
let tinyWithLimit = row("tinyLimit", 5 * mb)
let defaultView = quittableRows([tinyApp, smallEnough, tinyWithLimit], limitsGB: ["tinyLimit": 1])
check("apps under 20 MB are hidden by default", !defaultView.contains(tinyApp))
check("apps at 20 MB stay", defaultView.contains(smallEnough))
check("a tiny app with a limit stays, so its warning has a row", defaultView.contains(tinyWithLimit))

// Peak memory
let firstPeaks = updatedPeaks([:], rows: [row("app", 5 * gb)])
check("the first reading is the peak", firstPeaks == ["app": 5 * gb])
check("a higher reading raises the peak", updatedPeaks(firstPeaks, rows: [row("app", 6 * gb)]) == ["app": 6 * gb])
check("a lower reading keeps the peak", updatedPeaks(firstPeaks, rows: [row("app", 2 * gb)]) == ["app": 5 * gb])
check("a quit app forgets its peak", updatedPeaks(firstPeaks, rows: []) == [:])

// Memory breakdown
check("breakdown reads app, system, compressed and free", memoryBreakdownText(
    appBytes: gb * 81 / 10, wiredBytes: 2 * gb, compressedBytes: gb * 25 / 10, totalBytes: 16 * gb, stateLabel: "Normal"
) == "Normal · Apps 8.1 · System 2.0 · Compressed 2.5 · Free 3.4 GB")
check("free never goes below zero", memoryBreakdownText(
    appBytes: 20 * gb, wiredBytes: 0, compressedBytes: 0, totalBytes: 16 * gb, stateLabel: "Critical"
) == "Critical · Apps 20.0 · System 0.0 · Compressed 0.0 · Free 0.0 GB")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
