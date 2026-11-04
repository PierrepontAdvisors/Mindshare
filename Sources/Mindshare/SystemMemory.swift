import Darwin
import Foundation
import MemoryCore

struct SystemMemory: Equatable {
    let appBytes: UInt64
    let wiredBytes: UInt64
    let compressedBytes: UInt64
    let state: MemoryState

    var usedBytes: UInt64 { appBytes + wiredBytes + compressedBytes }
}

private let hostPort = mach_host_self()

func readSystemMemory() -> SystemMemory? {
    var stats = vm_statistics64()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
    let result = withUnsafeMutablePointer(to: &stats) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
        }
    }
    guard result == KERN_SUCCESS else {
        NSLog("Mindshare: could not read system memory (%d)", result)
        return nil
    }
    // App memory + wired + compressed: how Activity Monitor defines "Memory Used".
    let pageSize = UInt64(vm_kernel_page_size)
    let appPages = max(Int(stats.internal_page_count) - Int(stats.purgeable_count), 0)
    return SystemMemory(
        appBytes: UInt64(appPages) * pageSize,
        wiredBytes: UInt64(stats.wire_count) * pageSize,
        compressedBytes: UInt64(stats.compressor_page_count) * pageSize,
        state: memoryState(pressureLevel: readPressureLevel())
    )
}

private func readPressureLevel() -> Int32 {
    var level: Int32 = 0
    var size = MemoryLayout<Int32>.size
    guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return 0 }
    return level
}
