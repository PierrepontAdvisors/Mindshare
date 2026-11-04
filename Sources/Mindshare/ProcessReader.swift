import AppKit
import Darwin
import MemoryCore

// shortcut: private API that ties helpers to their app; if a macOS update removes it, helpers show as background rows.
private let responsiblePID: (Int32) -> Int32 = {
    typealias Lookup = @convention(c) (Int32) -> Int32
    let defaultSearch = UnsafeMutableRawPointer(bitPattern: -2)
    guard let symbol = dlsym(defaultSearch, "responsibility_get_pid_responsible_for_pid") else {
        NSLog("Mindshare: responsibility lookup missing, helpers will not group under their apps")
        return { $0 }
    }
    let lookup = unsafeBitCast(symbol, to: Lookup.self)
    return { lookup($0) }
}()

func sampleProcesses() -> [ProcessSample] {
    let owners = quittableOwners()
    return allPIDs().compactMap { pid in
        // Other users' system processes can't be read, so they are left out.
        guard let bytes = memoryFootprint(of: pid) else { return nil }
        let path = executablePath(of: pid)
        let name = (path as NSString).lastPathComponent
        return ProcessSample(name: name, bytes: bytes, owner: owners[responsiblePID(pid)], path: path)
    }
}

private func quittableOwners() -> [Int32: OwnerApp] {
    let apps = NSWorkspace.shared.runningApplications.filter(isQuittable)
    return ownersByPID(apps.map { app in
        let pid = app.processIdentifier
        return OwnerApp(id: app.bundleIdentifier ?? "pid:\(pid)", name: app.localizedName ?? "App \(pid)", pid: pid)
    })
}

private func isQuittable(_ app: NSRunningApplication) -> Bool {
    guard app.processIdentifier != getpid() else { return false }
    switch app.activationPolicy {
    case .regular: return true
    case .accessory: return app.bundleURL?.path.hasPrefix("/System/") == false
    default: return false
    }
}

private func allPIDs() -> [Int32] {
    let estimate = proc_listallpids(nil, 0)
    guard estimate > 0 else {
        NSLog("Mindshare: could not count processes")
        return []
    }
    // Double the estimate in case processes start between the two calls.
    var pids = [Int32](repeating: 0, count: Int(estimate) * 2)
    let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<Int32>.size))
    guard count > 0 else {
        NSLog("Mindshare: could not list processes")
        return []
    }
    return pids.prefix(Int(count)).filter { $0 > 0 }
}

// The same measure as Activity Monitor's Memory column; `ps` RSS leaves out compressed and swapped memory.
private func memoryFootprint(of pid: Int32) -> UInt64? {
    var info = rusage_info_v4()
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
        }
    }
    return result == 0 ? info.ri_phys_footprint : nil
}

private func executablePath(of pid: Int32) -> String {
    var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return "Unknown" }
    return String(cString: path)
}
